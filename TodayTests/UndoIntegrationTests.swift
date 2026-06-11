import Foundation
import SwiftData
import Testing
@testable import Today

/// Integration tests for SwiftData's automatic undo registration: with an
/// `UndoManager` attached to the context (as `AppState` does for the app),
/// changes made through `TaskManager` can be reverted with `undo()`.
///
/// Redo is intentionally not asserted here: community reports describe it as
/// flaky in SwiftData, so it is verified manually instead (and can be
/// disabled if it misbehaves).
@MainActor
@Suite("Undo integration")
struct UndoIntegrationTests {
    /// Fresh in-memory container with an undo manager attached, mirroring the
    /// app's configuration in `AppState`.
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodayTask.self, configurations: configuration)
        container.mainContext.undoManager = UndoManager()
        return container
    }

    /// A property change made through TaskManager is undoable.
    @Test("undo reverts a rename")
    func undoRevertsRename() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let task = TaskManager.createStructuredTask(title: "Original", in: context)
        // Drop the insertion from the undo stack so undo targets the rename
        // only (in-app, separate user actions land in separate event groups).
        context.undoManager?.removeAllActions()

        TaskManager.rename(task, to: "Renamed", in: context)
        #expect(task.title == "Renamed")

        context.undoManager?.undo()
        #expect(task.title == "Original")
    }

    /// An insertion made through TaskManager is undoable (the task vanishes).
    @Test("undo reverts an insertion")
    func undoRevertsInsert() throws {
        let container = try makeContainer()
        let context = container.mainContext

        TaskManager.addToToday(title: "Ephemeral", in: context)
        #expect(try context.fetch(FetchDescriptor<TodayTask>()).count == 1)

        context.undoManager?.undo()
        #expect(try context.fetch(FetchDescriptor<TodayTask>()).isEmpty)
    }

    /// A structured tree move (reparent) is undoable.
    @Test("undo reverts a tree move")
    func undoRevertsTreeMove() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let parent = TaskManager.createStructuredTask(title: "Parent", in: context)
        let loose = TaskManager.createStructuredTask(title: "Loose", in: context)
        context.undoManager?.removeAllActions()

        TaskManager.moveStructuredTask(loose, toParent: parent, in: context)
        #expect(loose.parent?.id == parent.id)

        context.undoManager?.undo()
        #expect(loose.parent == nil)
    }
}
