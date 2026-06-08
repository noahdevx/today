import Foundation
import OSLog
import SwiftData

/// Task lifecycle operations for the Today and Done areas.
///
/// Implemented as a stateless namespace of `@MainActor` functions that take the
/// `ModelContext` to act on. Keeping this logic out of the views makes it
/// unit-testable against an in-memory store and concentrates every SwiftData
/// mutation (and `save`) in one place.
@MainActor
enum TaskManager {
    // MARK: - Create

    /// Creates a task at the end of the Today column and persists it.
    ///
    /// `estimatedMinutes` is optional so an unestimated task is excluded from time
    /// totals rather than counted as zero. Returns the inserted task for callers
    /// (such as tests) that want to reference it.
    @discardableResult
    static func addToToday(
        title: String,
        estimatedMinutes: Int? = nil,
        in context: ModelContext
    ) -> TodayTask {
        let todayOrd = nextTodayOrder(in: context)
        let structOrd = nextStructuredOrder(parent: nil, in: context)
        let task = TodayTask(
            title: title,
            estimatedMinutes: estimatedMinutes,
            todayOrder: todayOrd,
            structuredOrder: structOrd
        )
        context.insert(task)
        save(context)
        return task
    }

    // MARK: - Reorder

    /// Reorders the Today column after a drag.
    ///
    /// `ordered` is the list exactly as currently displayed (Today order). The move
    /// is applied to that array and then `todayOrder` is renumbered 0..<n, so the
    /// stored order matches what the user sees and leaves no gaps to drift over time.
    static func reorderToday(
        _ ordered: [TodayTask],
        from source: IndexSet,
        to destination: Int,
        in context: ModelContext
    ) {
        var items = ordered
        items.move(fromOffsets: source, toOffset: destination)
        let now = Date.now
        for (index, task) in items.enumerated() {
            task.todayOrder = index
            task.updatedAt = now
        }
        save(context)
    }

    // MARK: - Complete / restore

    /// Marks a task done: stamps `doneAt` (which surfaces it in the Done area) and
    /// clears `todayOrder` so it leaves the Today column and can't collide with the
    /// renumbered order of the remaining Today tasks.
    static func complete(_ task: TodayTask, in context: ModelContext) {
        task.doneAt = .now
        task.todayOrder = nil
        task.updatedAt = .now
        save(context)
    }

    /// Reverses completion: clears `doneAt` and re-adds the task to the end of the
    /// Today column. The original position isn't restored (the user can drag it),
    /// which keeps ordering simple and free of collisions.
    static func restoreToToday(_ task: TodayTask, in context: ModelContext) {
        task.doneAt = nil
        task.todayOrder = nextTodayOrder(in: context)
        task.updatedAt = .now
        save(context)
    }

    // MARK: - Delete

    /// Permanently deletes a task (and, via the model's cascade rule, its subtree).
    static func delete(_ task: TodayTask, in context: ModelContext) {
        context.delete(task)
        save(context)
    }

    // MARK: - Structured area

    /// Creates a task in the structured tree under the given parent (or at root
    /// when `parent` is nil). The task is **not** added to Today—it only appears
    /// in the Structured column until the user drags it over.
    @discardableResult
    static func createStructuredTask(
        title: String,
        estimatedMinutes: Int? = nil,
        parent: TodayTask? = nil,
        in context: ModelContext
    ) -> TodayTask {
        let order = nextStructuredOrder(parent: parent, in: context)
        let task = TodayTask(
            title: title,
            estimatedMinutes: estimatedMinutes,
            structuredOrder: order,
            parent: parent
        )
        context.insert(task)
        save(context)
        return task
    }

    /// Adds an existing structured task to the Today column by assigning a
    /// `todayOrder`. If the task was previously completed, `doneAt` is cleared so
    /// it reappears as active. The task's position in the structured tree is
    /// unchanged (the "copy, don't move" semantic).
    static func addStructuredTaskToToday(_ task: TodayTask, in context: ModelContext) {
        guard task.todayOrder == nil else { return }
        task.todayOrder = nextTodayOrder(in: context)
        task.doneAt = nil
        task.updatedAt = .now
        save(context)
    }

    /// Removes a task from the Today column without deleting it. The task stays
    /// in the structured tree with its hierarchy and ordering intact.
    static func removeFromToday(_ task: TodayTask, in context: ModelContext) {
        task.todayOrder = nil
        task.updatedAt = .now
        save(context)
    }

    // MARK: - Find

    /// Looks up a task by its stable UUID. Returns `nil` when the ID doesn't match
    /// any persisted task (e.g. after a cascade delete).
    static func findTask(id: UUID, in context: ModelContext) -> TodayTask? {
        var descriptor = FetchDescriptor<TodayTask>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Helpers

    /// Next free Today position: one past the current maximum, or 0 when Today is
    /// empty. Considers only active Today tasks (have `todayOrder`, not done).
    private static func nextTodayOrder(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<TodayTask>(
            predicate: #Predicate { $0.todayOrder != nil && $0.doneAt == nil }
        )
        let activeTasks = (try? context.fetch(descriptor)) ?? []
        let maxOrder = activeTasks.compactMap(\.todayOrder).max()
        return (maxOrder ?? -1) + 1
    }

    /// Next free `structuredOrder` among siblings of the given parent. For root
    /// tasks (`parent` nil) it scans all root-level tasks; for children it reads
    /// the parent's `children` array. Returns 0 when there are no siblings yet.
    private static func nextStructuredOrder(parent: TodayTask?, in context: ModelContext) -> Int {
        let siblings: [TodayTask]
        if let parent {
            siblings = parent.children
        } else {
            let descriptor = FetchDescriptor<TodayTask>()
            let all = (try? context.fetch(descriptor)) ?? []
            siblings = all.filter { $0.parent == nil }
        }
        let maxOrder = siblings.map(\.structuredOrder).max()
        return (maxOrder ?? -1) + 1
    }

    /// Logger for persistence failures. Unlike `assertionFailure` (compiled out in
    /// release), this is recorded in the unified log (Console.app) in every build.
    private static let logger = Logger(subsystem: "com.today.app", category: "TaskManager")

    /// Saves the context, surfacing failures during development. SwiftData
    /// autosaves, but an explicit save makes the write deterministic for the UI
    /// and for tests.
    private static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            // Record in all builds (survives release), and trap in debug to catch
            // it early during development.
            logger.error("Failed to save the model context: \(error.localizedDescription)")
            assertionFailure("Failed to save the model context: \(error)")
        }
    }
}
