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
        let order = nextTodayOrder(in: context)
        let task = TodayTask(
            title: title,
            estimatedMinutes: estimatedMinutes,
            todayOrder: order,
            // Provisional: reuse the Today position as the structured position too.
            // The Structured area is a placeholder until Step 4, which will own the
            // real structuredOrder assignment.
            structuredOrder: order
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
