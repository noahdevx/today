import Foundation
import SwiftData
import Testing
@testable import Today

/// Unit tests for `TaskManager` against a real (in-memory) SwiftData store: add,
/// reorder, complete, restore, and delete. Runs on the main actor because the
/// manager and `mainContext` are main-actor isolated.
@MainActor
@Suite("TaskManager")
struct TaskManagerTests {
    /// Fresh in-memory container per test. The caller keeps it in a local for the
    /// test's lifetime; releasing it would tear down the context mid-test.
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: TodayTask.self, configurations: configuration)
    }

    /// Adding tasks places them in Today with sequential, gap-free order.
    @Test("addToToday inserts into Today with sequential order")
    func addAssignsSequentialOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let first = TaskManager.addToToday(title: "A", in: context)
        let second = TaskManager.addToToday(title: "B", estimatedMinutes: 30, in: context)

        #expect(first.todayOrder == 0)
        #expect(second.todayOrder == 1)
        #expect(first.isInToday)
        #expect(second.estimatedMinutes == 30)
        #expect(try context.fetch(FetchDescriptor<TodayTask>()).count == 2)
    }

    /// Completing stamps `doneAt` and removes the task from the Today column.
    @Test("complete stamps doneAt and leaves Today")
    func completeMovesToDone() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let task = TaskManager.addToToday(title: "A", in: context)
        TaskManager.complete(task, in: context)

        #expect(task.isDone)
        #expect(task.doneAt != nil)
        #expect(task.todayOrder == nil)
        #expect(!task.isInToday)
    }

    /// Restoring clears `doneAt` and re-adds the task to the end of Today.
    @Test("restoreToToday clears doneAt and re-adds to the end of Today")
    func restoreReturnsToToday() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let kept = TaskManager.addToToday(title: "kept", in: context) // order 0
        let done = TaskManager.addToToday(title: "done", in: context) // order 1
        TaskManager.complete(done, in: context)
        TaskManager.restoreToToday(done, in: context)

        #expect(!done.isDone)
        #expect(done.doneAt == nil)
        // `kept` still holds order 0, so the restored task lands right after it.
        #expect(kept.todayOrder == 0)
        #expect(done.todayOrder == 1)
    }

    /// Reordering renumbers `todayOrder` to match the displayed order.
    @Test("reorderToday renumbers todayOrder to match the new order")
    func reorderRenumbers() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let taskA = TaskManager.addToToday(title: "A", in: context) // 0
        let taskB = TaskManager.addToToday(title: "B", in: context) // 1
        let taskC = TaskManager.addToToday(title: "C", in: context) // 2

        // Move the last item (C) to the front -> [C, A, B].
        TaskManager.reorderToday([taskA, taskB, taskC], from: IndexSet(integer: 2), to: 0, in: context)

        #expect(taskC.todayOrder == 0)
        #expect(taskA.todayOrder == 1)
        #expect(taskB.todayOrder == 2)
    }

    /// Deleting removes the task from the store.
    @Test("delete removes the task from the store")
    func deleteRemovesTask() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let task = TaskManager.addToToday(title: "A", in: context)
        TaskManager.delete(task, in: context)

        #expect(try context.fetch(FetchDescriptor<TodayTask>()).isEmpty)
    }
}

/// Pure-function tests for the duration formatter (no store needed).
@Suite("TimeFormatting")
struct TimeFormattingTests {
    /// The formatter follows the spec across the boundary cases.
    @Test(
        "durationLabel formats minutes per the spec",
        arguments: [
            (0, "0m"),
            (30, "30m"),
            (45, "45m"),
            (60, "1h"),
            (90, "1h 30m"),
            (120, "2h"),
            (125, "2h 5m")
        ]
    )
    func durationLabelFormatsMinutes(minutes: Int, expected: String) {
        #expect(TimeFormatting.durationLabel(minutes: minutes) == expected)
    }
}
