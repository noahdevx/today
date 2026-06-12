import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Today area (left-most column): cross-project, single-column ordering of what to
/// tackle today. Backed by SwiftData -- tasks are added, reordered by dragging,
/// completed, and deleted here -- and the header shows the live total estimate.
struct TodayAreaView: View {
    /// Bound to the parent so the header's Done button shows/hides the Done column.
    @Binding var showDone: Bool

    /// The shared context for all mutations (injected via `.modelContainer`).
    @Environment(\.modelContext) private var modelContext
    /// Selection engine; carries the in-flight dragged task for drops.
    @Environment(SelectionEngine.self) private var selectionEngine

    /// Active Today tasks: placed in Today (`todayOrder != nil`) and not yet done,
    /// sorted by their Today position. The query updates automatically on changes.
    @Query(
        filter: #Predicate<TodayTask> { $0.todayOrder != nil && $0.doneAt == nil },
        sort: \TodayTask.todayOrder
    )
    private var tasks: [TodayTask]

    /// Draft title for the new-task field.
    @State private var newTitle = ""
    /// Draft estimate (minutes) for the new-task field; empty means "no estimate".
    @State private var newMinutes = ""
    /// True while a dragged item hovers over this column (visual drop feedback).
    @State private var isDropTargeted = false
    /// Focus of the new-task title field; set by the Cmd-N shortcut and after
    /// adding a task (for rapid consecutive entry).
    @FocusState private var isNewTaskFocused: Bool

    var body: some View {
        AreaColumn(title: "Today", totalTime: tasks.totalEstimateLabel, accent: .yellow) {
            VStack(alignment: .leading, spacing: 10) {
                doneToggle
                addRow
                taskList
            }
        }
        // Visual feedback: highlight the column border when a structured task
        // is dragged over it.
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(0.5), lineWidth: 2)
            }
        }
        // Accept drops of structured tasks (resolved via the selection
        // engine's in-flight drag state, which is synchronous and reliable
        // for in-app drags).
        .onDrop(
            of: [.plainText],
            delegate: TodayColumnDropDelegate(
                engine: selectionEngine,
                context: modelContext,
                isTargeted: $isDropTargeted
            )
        )
        // Invisible button that gives the panel a Cmd-N "new task" shortcut:
        // it focuses the title field. opacity(0) keeps the button in the
        // hierarchy (so the shortcut stays active) without rendering anything.
        .background {
            Button("New Task") { isNewTaskFocused = true }
                .keyboardShortcut("n")
                .opacity(0)
        }
    }

    // MARK: - Subviews

    /// Button that toggles the Done column; the icon reflects open/closed state.
    /// Cmd-D toggles it from the keyboard while the panel is key.
    private var doneToggle: some View {
        Button {
            showDone.toggle()
        } label: {
            Label("Done", systemImage: showDone ? "chevron.left" : "checkmark.circle")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .keyboardShortcut("d")
    }

    /// New-task input: a title field plus an optional minutes field. Submitting
    /// either field, or pressing the add button, creates the task.
    private var addRow: some View {
        HStack(spacing: 6) {
            TextField("Add a task", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .focused($isNewTaskFocused)
                .onSubmit(addTask)
            TextField("min", text: $newMinutes)
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
                .onSubmit(addTask)
            Button(action: addTask) {
                Image(systemName: "plus")
            }
            // Disabled until there's a non-empty title to add.
            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// The ordered, drag-reorderable list of today's tasks. `.onMove` enables the
    /// native drag handle; swiping a row reveals Delete. The head row is the
    /// "Now" task and gets a highlighted treatment. A ScrollViewReader keeps
    /// the keyboard/search selection in view.
    private var taskList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(tasks) { task in
                    // Hover reporting and the cross-area highlight come from
                    // the shared taskSelectable modifier inside todayRow.
                    todayRow(for: task)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                TaskManager.delete(task, in: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        // Anchor for ScrollViewReader (selection follow).
                        .id(task.id)
                }
                .onMove(perform: moveTasks)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Scroll requests target this list on arrow-key moves and search
            // jumps so the relevant row is always brought into view.
            .onChange(of: selectionEngine.scrollRequests) { _, requests in
                guard let target = requests.first(where: { $0.area == .today }) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(target.taskID)
                }
            }
        }
        // Let the list fill the remaining column height.
        .frame(maxHeight: .infinity)
    }

    /// One Today row. The first task in the column is the "Now" task - the one
    /// being worked on right now - and is emphasized with a NOW badge and a
    /// yellow background so the eye lands there first. Rendering stays inside
    /// the single ForEach so `.onMove` reordering keeps working; whichever task
    /// is dragged to the top becomes Now automatically. While the task is
    /// being edited the static row swaps for the inline editor.
    @ViewBuilder
    private func todayRow(for task: TodayTask) -> some View {
        let isNow = task.id == tasks.first?.id
        VStack(alignment: .leading, spacing: 2) {
            if isNow {
                Text("NOW")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
            if selectionEngine.isEditing(task.id, in: .today) {
                InlineTaskEditor(task: task, area: .today)
            } else {
                TaskRow(task: task) {
                    TaskManager.complete(task, in: modelContext)
                }
            }
        }
        .padding(isNow ? 6 : 0)
        .background {
            if isNow {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.yellow.opacity(0.25))
            }
        }
        .taskSelectable(task, in: .today)
    }

    // MARK: - Actions

    /// Validates and creates a task from the draft fields, then clears them. A
    /// non-positive minutes value is treated as "no estimate".
    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let minutes = Int(newMinutes.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
        TaskManager.addToToday(title: title, estimatedMinutes: minutes, in: modelContext)
        newTitle = ""
        newMinutes = ""
        // Keep the title field focused so several tasks can be entered in a row.
        isNewTaskFocused = true
    }

    /// Forwards a drag-reorder to the manager, which renumbers `todayOrder`.
    private func moveTasks(from source: IndexSet, to destination: Int) {
        TaskManager.reorderToday(tasks, from: source, to: destination, in: modelContext)
    }
}

// MARK: - Column drop delegate

/// Drop delegate for the whole Today column: dropping a structured task here
/// adds it to Today (the task also stays in the structured tree). The dragged
/// task is resolved through `SelectionEngine.draggedTaskID`, set by the drag
/// source in the structured tree.
@MainActor
struct TodayColumnDropDelegate: DropDelegate {
    /// Shared engine carrying the in-flight dragged task ID.
    let engine: SelectionEngine
    /// Context for the add-to-Today mutation.
    let context: ModelContext
    /// Targeting flag bound to the column's border highlight.
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        engine.draggedTaskID != nil
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let draggedID = engine.draggedTaskID,
              let task = TaskManager.findTask(id: draggedID, in: context) else { return false }
        engine.draggedTaskID = nil
        TaskManager.addStructuredTaskToToday(task, in: context)
        return true
    }
}
