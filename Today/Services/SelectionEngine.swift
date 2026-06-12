import Foundation
import SwiftData

/// The keyboard-navigable areas, in left-to-right visual order as laid out in
/// ContentView. The minimap is intentionally absent: it is a passive
/// visualization with no selectable rows.
enum AreaKind: Int, CaseIterable {
    case today
    case done
    case structured
    case scheduled
    case waiting
}

/// App-wide selection, keyboard-navigation, and inline-editing state.
///
/// Created once by ContentView and injected via `@Environment`. Row views read
/// it to draw the selection ring and to swap in inline editors; ContentView
/// routes key commands (arrows, Delete, Space, Escape) to the methods below.
///
/// Two pieces of state are deliberately lifted up here instead of living in
/// individual views:
/// - `collapsedIDs`: which structured nodes are collapsed. Keyboard navigation
///   and search jumps must know (and change) which rows are actually visible.
/// - `isDoneVisible`: whether the Done column is shown. Left/right navigation
///   skips a hidden Done column, and a search jump to a done task opens it.
@MainActor
@Observable
final class SelectionEngine {
    /// Inline-editable fields of a task row.
    enum EditingField {
        case title
        case minutes
    }

    /// Vertical navigation direction (up/down arrow keys).
    enum VerticalMove {
        case up
        case down
    }

    /// The area that currently owns the keyboard cursor, or nil when none.
    var focusedArea: AreaKind?
    /// The selected task, or nil when nothing is selected.
    var selectedTaskID: UUID?
    /// Which inline field of the selected task is being edited (nil = none).
    var editingField: EditingField?
    /// Collapsed structured nodes; a node's subtree is hidden while its ID is
    /// in this set. Nodes default to expanded (absent).
    var collapsedIDs: Set<UUID> = []
    /// Whether the Done column is shown. Owned here (not by ContentView) so
    /// navigation and search jumps can open/skip the column.
    var isDoneVisible = false
    /// The task currently being dragged from the structured tree (nil when no
    /// drag is in flight). Written by the drag source and read by drop targets
    /// to suppress invalid-target feedback (self / own subtree) synchronously,
    /// which the async NSItemProvider payload alone can't provide.
    var draggedTaskID: UUID?

    // MARK: - Selection

    /// Selects a task (pointer click or programmatic) and ends any editing.
    func select(_ taskID: UUID?, in area: AreaKind) {
        focusedArea = area
        selectedTaskID = taskID
        editingField = nil
    }

    /// True when the given task, in the given area, is the current selection.
    /// The area matters because the same task can appear in several columns
    /// (e.g. Today and Structured); only its row in the focused area shows
    /// the selection ring.
    func isSelected(_ taskID: UUID, in area: AreaKind) -> Bool {
        selectedTaskID == taskID && focusedArea == area
    }

    /// True when the given task, in the given area, is in inline-edit mode.
    func isEditing(_ taskID: UUID, in area: AreaKind) -> Bool {
        editingField != nil && selectedTaskID == taskID && focusedArea == area
    }

    /// Begins inline editing of the selected task's title (Space key).
    func beginEditingTitle() {
        guard selectedTaskID != nil else { return }
        editingField = .title
    }

    /// Handles Escape with standard two-stage behavior: cancel editing first,
    /// then clear the selection. Returns true when the key was consumed, so
    /// the caller only hides the panel once nothing was left to dismiss.
    func handleEscape() -> Bool {
        if editingField != nil {
            editingField = nil
            return true
        }
        if selectedTaskID != nil {
            selectedTaskID = nil
            focusedArea = nil
            return true
        }
        return false
    }

    // MARK: - Tree collapse

    /// Toggles a structured node between collapsed and expanded.
    func toggleCollapsed(_ taskID: UUID) {
        if collapsedIDs.contains(taskID) {
            collapsedIDs.remove(taskID)
        } else {
            collapsedIDs.insert(taskID)
        }
    }

    /// Expands every collapsed ancestor of the given task so it is visible in
    /// the structured tree (used when jumping to a search result that sits
    /// inside a collapsed subtree).
    func revealInStructured(_ task: TodayTask) {
        for ancestor in task.ancestors {
            collapsedIDs.remove(ancestor.id)
        }
    }

    // MARK: - Keyboard navigation

    /// Moves the selection one row up/down inside the focused area. With no
    /// selection yet, enters the list at the edge (top for down, bottom for
    /// up). The selection stops at the ends rather than wrapping, matching
    /// standard macOS list behavior.
    func moveSelection(_ move: VerticalMove, context: ModelContext) {
        let area = focusedArea ?? .today
        let ids = visibleTaskIDs(in: area, context: context)
        guard !ids.isEmpty else { return }
        focusedArea = area
        editingField = nil

        guard let current = selectedTaskID, let index = ids.firstIndex(of: current) else {
            // No (valid) selection: enter the list at the near edge.
            selectedTaskID = (move == .down) ? ids.first : ids.last
            return
        }
        let next = (move == .down) ? min(index + 1, ids.count - 1) : max(index - 1, 0)
        selectedTaskID = ids[next]
    }

    /// Right arrow on a structured selection: expands a collapsed node, or
    /// steps into the first child when already expanded (standard outline
    /// behavior). No-op outside the structured area or on leaves.
    func expandSelection(context: ModelContext) {
        guard focusedArea == .structured,
              let selectedID = selectedTaskID,
              let task = TaskManager.findTask(id: selectedID, in: context),
              !task.children.isEmpty else { return }
        if collapsedIDs.contains(selectedID) {
            collapsedIDs.remove(selectedID)
        } else if let firstChild = task.sortedChildren.first {
            selectedTaskID = firstChild.id
        }
    }

    /// Left arrow on a structured selection: collapses an expanded node, or
    /// moves the selection up to the parent when the node is a leaf or
    /// already collapsed (standard outline behavior).
    func collapseSelection(context: ModelContext) {
        guard focusedArea == .structured,
              let selectedID = selectedTaskID,
              let task = TaskManager.findTask(id: selectedID, in: context) else { return }
        if !task.children.isEmpty, !collapsedIDs.contains(selectedID) {
            collapsedIDs.insert(selectedID)
        } else if let parent = task.parent {
            selectedTaskID = parent.id
        }
    }

    /// Tab on a structured selection: nests the task under its previous
    /// sibling (outliner-style indent) and expands that new parent so the
    /// task stays visible. No-op when the task has no previous sibling.
    func indentSelection(context: ModelContext) {
        guard focusedArea == .structured,
              let selectedID = selectedTaskID,
              let task = TaskManager.findTask(id: selectedID, in: context) else { return }
        guard let newParent = TaskManager.indentStructuredTask(task, in: context) else { return }
        collapsedIDs.remove(newParent.id)
    }

    /// Shift-Tab on a structured selection: moves the task out of its parent,
    /// placing it right after the parent (outliner-style outdent). No-op for
    /// root tasks.
    func outdentSelection(context: ModelContext) {
        guard focusedArea == .structured,
              let selectedID = selectedTaskID,
              let task = TaskManager.findTask(id: selectedID, in: context) else { return }
        TaskManager.outdentStructuredTask(task, in: context)
    }

    /// Deletes the selected task and keeps the keyboard flow going by
    /// selecting the row that takes its place (or the new last row).
    func deleteSelection(context: ModelContext) {
        guard let area = focusedArea,
              let current = selectedTaskID,
              let task = TaskManager.findTask(id: current, in: context) else { return }
        let index = visibleTaskIDs(in: area, context: context).firstIndex(of: current)
        TaskManager.delete(task, in: context)

        let remaining = visibleTaskIDs(in: area, context: context)
        if let index {
            selectedTaskID = remaining.indices.contains(index) ? remaining[index] : remaining.last
        } else {
            selectedTaskID = remaining.first
        }
        editingField = nil
    }

    /// Advances inline editing from the minutes field to the next task's
    /// title (the "Tab through the list" behavior). Editing simply ends on
    /// the last task.
    func editNextTask(context: ModelContext) {
        guard let area = focusedArea else {
            editingField = nil
            return
        }
        let ids = visibleTaskIDs(in: area, context: context)
        guard let current = selectedTaskID,
              let index = ids.firstIndex(of: current),
              index + 1 < ids.count else {
            editingField = nil
            return
        }
        selectedTaskID = ids[index + 1]
        editingField = .title
    }

    // MARK: - Search jump

    /// Jumps to a task from the search dropdown: reveals it (expanding any
    /// collapsed ancestors, opening the Done column when needed), focuses its
    /// home area, and selects it.
    func jump(to task: TodayTask) {
        revealInStructured(task)
        let area = homeArea(of: task)
        if area == .done {
            isDoneVisible = true
        }
        focusedArea = area
        selectedTaskID = task.id
        editingField = nil
    }

    /// The most specific area a task belongs to, mirroring the area queries:
    /// active Today membership wins, then Done (completed today only - older
    /// completed tasks are only reachable in the structured tree), then
    /// Scheduled, Waiting, and finally the structured tree (where every task
    /// lives).
    func homeArea(of task: TodayTask) -> AreaKind {
        if task.isInToday && !task.isDone { return .today }
        if task.isDone {
            let startOfToday = Calendar.current.startOfDay(for: .now)
            if let doneAt = task.doneAt, doneAt >= startOfToday { return .done }
            return .structured
        }
        if task.isScheduled { return .scheduled }
        if task.isWaiting { return .waiting }
        return .structured
    }

    // MARK: - Visible order

    /// The IDs of the tasks currently visible in the given area, top to
    /// bottom. Each case mirrors the corresponding area view's `@Query`
    /// (same predicate and sort) so keyboard navigation matches the screen.
    func visibleTaskIDs(in area: AreaKind, context: ModelContext) -> [UUID] {
        switch area {
        case .today:
            let descriptor = FetchDescriptor<TodayTask>(
                predicate: #Predicate { $0.todayOrder != nil && $0.doneAt == nil },
                sortBy: [SortDescriptor(\.todayOrder)]
            )
            return fetchIDs(descriptor, context: context)

        case .done:
            // Same "completed today" boundary as DoneAreaView.
            let startOfToday = Calendar.current.startOfDay(for: .now)
            let descriptor = FetchDescriptor<TodayTask>(
                predicate: #Predicate { task in
                    if let doneAt = task.doneAt {
                        return doneAt >= startOfToday
                    } else {
                        return false
                    }
                },
                sortBy: [SortDescriptor(\.doneAt, order: .reverse)]
            )
            return fetchIDs(descriptor, context: context)

        case .structured:
            return structuredVisibleIDs(context: context)

        case .scheduled:
            let descriptor = FetchDescriptor<TodayTask>(
                predicate: #Predicate { $0.scheduledAt != nil && $0.doneAt == nil },
                sortBy: [SortDescriptor(\.scheduledAt)]
            )
            return fetchIDs(descriptor, context: context)

        case .waiting:
            let descriptor = FetchDescriptor<TodayTask>(
                predicate: #Predicate { $0.startedWaitingAt != nil && $0.doneAt == nil },
                sortBy: [SortDescriptor(\.startedWaitingAt)]
            )
            return fetchIDs(descriptor, context: context)
        }
    }

    /// Runs a fetch and reduces the result to IDs (navigation only needs
    /// identity and order).
    private func fetchIDs(_ descriptor: FetchDescriptor<TodayTask>, context: ModelContext) -> [UUID] {
        ((try? context.fetch(descriptor)) ?? []).map(\.id)
    }

    /// Depth-first walk of the structured tree in display order, skipping the
    /// subtrees of collapsed nodes - exactly the rows StructuredAreaView
    /// renders.
    private func structuredVisibleIDs(context: ModelContext) -> [UUID] {
        let descriptor = FetchDescriptor<TodayTask>(
            sortBy: [SortDescriptor(\.structuredOrder)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        let roots = all.filter { $0.parent == nil }

        var result: [UUID] = []
        // Local recursion keeps the traversal logic next to its only caller.
        func visit(_ task: TodayTask) {
            result.append(task.id)
            guard !collapsedIDs.contains(task.id) else { return }
            for child in task.sortedChildren {
                visit(child)
            }
        }
        for root in roots {
            visit(root)
        }
        return result
    }
}
