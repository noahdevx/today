import Foundation
import SwiftData

/// Inline editing, structured-tree moves, and search.
///
/// Split out of `TaskManager.swift` to keep both files comfortably small;
/// the operations here back PR 5's keyboard editing, tree drag & drop, and
/// the search dropdown. All writes go through `TaskManager.save`.
extension TaskManager {
    // MARK: - Edit

    /// Renames a task from the inline title editor. Whitespace is trimmed and
    /// empty titles are rejected so a task can't lose its name by accident.
    static func rename(_ task: TodayTask, to title: String, in context: ModelContext) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        task.title = trimmed
        task.updatedAt = .now
        save(context)
    }

    /// Updates a task's estimate from the inline minutes editor. Non-positive
    /// values clear the estimate (nil) so the task drops out of time totals
    /// instead of counting as zero.
    static func setEstimate(_ task: TodayTask, minutes: Int?, in context: ModelContext) {
        let normalized = minutes.flatMap { $0 > 0 ? $0 : nil }
        guard normalized != task.estimatedMinutes else { return }
        task.estimatedMinutes = normalized
        task.updatedAt = .now
        save(context)
    }

    // MARK: - Structured tree moves

    /// Moves a task to a new position in the structured tree: a new parent
    /// (nil = root level) and a position among the new siblings (nil = append
    /// at the end). `index` is interpreted against the sibling list *without*
    /// the moving task, which matches how drop targets compute positions.
    ///
    /// No-ops when the destination would create a cycle: a task can't become
    /// a child of itself or of any task inside its own subtree.
    static func moveStructuredTask(
        _ task: TodayTask,
        toParent newParent: TodayTask?,
        at index: Int? = nil,
        in context: ModelContext
    ) {
        // Cycle guard: reject self-parenting and drops into the task's subtree.
        if let newParent {
            guard newParent.id != task.id, !newParent.isDescendant(of: task) else { return }
        }

        // Close the gap in the old sibling list (the moving task excluded).
        let oldSiblings = structuredSiblings(under: task.parent, excluding: task, in: context)
        renumberStructured(oldSiblings)

        // Insert into the new sibling list at the clamped position, reparent,
        // and renumber so structuredOrder stays sequential and gap-free.
        var newSiblings = structuredSiblings(under: newParent, excluding: task, in: context)
        let position = min(max(index ?? newSiblings.count, 0), newSiblings.count)
        newSiblings.insert(task, at: position)
        task.parent = newParent
        renumberStructured(newSiblings)

        task.updatedAt = .now
        save(context)
    }

    /// Moves `task` so it sits immediately before `reference` under the
    /// reference's parent. Convenience for drop targets ("insert above this
    /// row"); shares the cycle guard of the designated move function.
    static func moveStructuredTask(
        _ task: TodayTask,
        before reference: TodayTask,
        in context: ModelContext
    ) {
        guard reference.id != task.id else { return }
        let siblings = structuredSiblings(under: reference.parent, excluding: task, in: context)
        guard let index = siblings.firstIndex(where: { $0.id == reference.id }) else { return }
        moveStructuredTask(task, toParent: reference.parent, at: index, in: context)
    }

    /// Moves `task` so it sits immediately after `reference` under the
    /// reference's parent. Convenience for drop targets ("insert below this
    /// row"); shares the cycle guard of the designated move function.
    static func moveStructuredTask(
        _ task: TodayTask,
        after reference: TodayTask,
        in context: ModelContext
    ) {
        guard reference.id != task.id else { return }
        let siblings = structuredSiblings(under: reference.parent, excluding: task, in: context)
        guard let index = siblings.firstIndex(where: { $0.id == reference.id }) else { return }
        moveStructuredTask(task, toParent: reference.parent, at: index + 1, in: context)
    }

    /// Nests `task` under its previous sibling (outliner-style indent, bound
    /// to Tab in the structured tree). Returns the new parent so the caller
    /// can expand it, or nil when the task is first among its siblings and
    /// there is nothing to indent under.
    @discardableResult
    static func indentStructuredTask(_ task: TodayTask, in context: ModelContext) -> TodayTask? {
        let siblings = structuredSiblings(under: task.parent, in: context)
        guard let index = siblings.firstIndex(where: { $0.id == task.id }), index > 0 else { return nil }
        let newParent = siblings[index - 1]
        moveStructuredTask(task, toParent: newParent, in: context)
        return newParent
    }

    /// Moves `task` out of its parent, placing it immediately after that
    /// parent among the parent's siblings (outliner-style outdent, bound to
    /// Shift-Tab in the structured tree). No-op for root tasks.
    static func outdentStructuredTask(_ task: TodayTask, in context: ModelContext) {
        guard let parent = task.parent else { return }
        moveStructuredTask(task, after: parent, in: context)
    }

    // MARK: - Search

    /// Case-insensitive title search for the search dropdown. Empty queries
    /// return nothing; results are capped at `limit` and ordered by most
    /// recently updated first so fresh tasks surface on top.
    static func searchTasks(
        matching query: String,
        limit: Int = 20,
        in context: ModelContext
    ) -> [TodayTask] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        var descriptor = FetchDescriptor<TodayTask>(
            predicate: #Predicate { $0.title.localizedStandardContains(trimmed) },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Helpers

    /// Siblings under the given parent (nil = root tasks) in structured order,
    /// optionally excluding one task. The exclusion is used while moving that
    /// task: its old list is renumbered without it, and its new list computes
    /// insert positions without it.
    private static func structuredSiblings(
        under parent: TodayTask?,
        excluding excluded: TodayTask? = nil,
        in context: ModelContext
    ) -> [TodayTask] {
        let all: [TodayTask]
        if let parent {
            all = parent.sortedChildren
        } else {
            let descriptor = FetchDescriptor<TodayTask>(
                sortBy: [SortDescriptor(\.structuredOrder)]
            )
            let fetched = (try? context.fetch(descriptor)) ?? []
            all = fetched.filter { $0.parent == nil }
        }
        guard let excluded else { return all }
        return all.filter { $0.id != excluded.id }
    }

    /// Renumbers `structuredOrder` 0..<n to match the array order, stamping
    /// `updatedAt` only on tasks whose position actually changed.
    private static func renumberStructured(_ tasks: [TodayTask]) {
        let now = Date.now
        for (index, task) in tasks.enumerated() where task.structuredOrder != index {
            task.structuredOrder = index
            task.updatedAt = now
        }
    }
}
