import Foundation
import SwiftData
import Testing
@testable import Today

/// Unit tests for `TaskManager`'s editing, structured-tree move, and search
/// operations (the `TaskManager+Editing.swift` extension) against a real
/// (in-memory) SwiftData store. Runs on the main actor because the manager
/// and `mainContext` are main-actor isolated.
@MainActor
@Suite("TaskManager editing and tree moves")
struct TaskManagerEditingTests {
    /// Fresh in-memory container per test. The caller keeps it in a local for
    /// the test's lifetime; releasing it would tear down the context mid-test.
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: TodayTask.self, configurations: configuration)
    }

    // MARK: - Edit

    /// rename trims whitespace and updates the title.
    @Test("rename updates the title and trims whitespace")
    func renameUpdatesTitle() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let task = TaskManager.createStructuredTask(title: "Old", in: context)
        TaskManager.rename(task, to: "  New name  ", in: context)

        #expect(task.title == "New name")
    }

    /// rename rejects empty (or whitespace-only) titles.
    @Test("rename rejects an empty title")
    func renameRejectsEmptyTitle() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let task = TaskManager.createStructuredTask(title: "Keep me", in: context)
        TaskManager.rename(task, to: "   ", in: context)

        #expect(task.title == "Keep me")
    }

    /// setEstimate stores positive values and clears non-positive ones.
    @Test(
        "setEstimate stores positive minutes and clears non-positive",
        arguments: [(45, 45), (0, nil), (-5, nil)] as [(Int, Int?)]
    )
    func setEstimateNormalizes(input: Int, expected: Int?) throws {
        let container = try makeContainer()
        let context = container.mainContext

        let task = TaskManager.createStructuredTask(title: "T", estimatedMinutes: 10, in: context)
        TaskManager.setEstimate(task, minutes: input, in: context)

        #expect(task.estimatedMinutes == expected)
    }

    // MARK: - Structured tree moves

    /// Reordering within the same parent renumbers siblings to match.
    @Test("moveStructuredTask reorders siblings under the same parent")
    func moveReordersSiblings() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let taskA = TaskManager.createStructuredTask(title: "A", in: context) // 0
        let taskB = TaskManager.createStructuredTask(title: "B", in: context) // 1
        let taskC = TaskManager.createStructuredTask(title: "C", in: context) // 2

        // Move C to the front of the root level -> [C, A, B].
        TaskManager.moveStructuredTask(taskC, toParent: nil, at: 0, in: context)

        #expect(taskC.structuredOrder == 0)
        #expect(taskA.structuredOrder == 1)
        #expect(taskB.structuredOrder == 2)
        #expect(taskC.parent == nil)
    }

    /// Moving under a new parent reparents and renumbers both sibling lists.
    @Test("moveStructuredTask reparents a task into another subtree")
    func moveReparents() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let parent = TaskManager.createStructuredTask(title: "Parent", in: context) // root 0
        let child = TaskManager.createStructuredTask(title: "Child", parent: parent, in: context)
        let loose = TaskManager.createStructuredTask(title: "Loose", in: context) // root 1

        // Nest "Loose" under "Parent", after "Child".
        TaskManager.moveStructuredTask(loose, toParent: parent, in: context)

        #expect(loose.parent?.id == parent.id)
        #expect(child.structuredOrder == 0)
        #expect(loose.structuredOrder == 1)
        // Root level closed the gap: only "Parent" remains at order 0.
        #expect(parent.structuredOrder == 0)
    }

    /// Moving a child out to the root level works and renumbers the old parent.
    @Test("moveStructuredTask moves a child back to the root level")
    func movePromotesChildToRoot() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let parent = TaskManager.createStructuredTask(title: "Parent", in: context) // root 0
        let childA = TaskManager.createStructuredTask(title: "A", parent: parent, in: context) // 0
        let childB = TaskManager.createStructuredTask(title: "B", parent: parent, in: context) // 1

        // Promote A to the root level, before "Parent".
        TaskManager.moveStructuredTask(childA, toParent: nil, at: 0, in: context)

        #expect(childA.parent == nil)
        #expect(childA.structuredOrder == 0)
        #expect(parent.structuredOrder == 1)
        // The old sibling list closed its gap.
        #expect(childB.structuredOrder == 0)
    }

    /// before/after variants insert relative to a reference sibling.
    @Test("moveStructuredTask before/after inserts around the reference")
    func moveBeforeAfterReference() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let parent = TaskManager.createStructuredTask(title: "Parent", in: context)
        let childA = TaskManager.createStructuredTask(title: "A", parent: parent, in: context)
        let childB = TaskManager.createStructuredTask(title: "B", parent: parent, in: context)
        let loose = TaskManager.createStructuredTask(title: "Loose", in: context)

        // Drop "Loose" just above B -> [A, Loose, B].
        TaskManager.moveStructuredTask(loose, before: childB, in: context)
        #expect(loose.parent?.id == parent.id)
        #expect(parent.sortedChildren.map(\.title) == ["A", "Loose", "B"])

        // Then move it just after B -> [A, B, Loose].
        TaskManager.moveStructuredTask(loose, after: childB, in: context)
        #expect(parent.sortedChildren.map(\.title) == ["A", "B", "Loose"])

        _ = childA // fixture kept alive in the store
    }

    /// indent nests a task under its previous sibling; the first sibling has
    /// nothing to indent under and is left alone.
    @Test("indentStructuredTask nests under the previous sibling")
    func indentNestsUnderPreviousSibling() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let first = TaskManager.createStructuredTask(title: "First", in: context) // root 0
        let second = TaskManager.createStructuredTask(title: "Second", in: context) // root 1

        let newParent = TaskManager.indentStructuredTask(second, in: context)

        #expect(newParent?.id == first.id)
        #expect(second.parent?.id == first.id)
        #expect(first.sortedChildren.map(\.title) == ["Second"])

        // "First" is now the only root; indenting it is a no-op.
        #expect(TaskManager.indentStructuredTask(first, in: context) == nil)
        #expect(first.parent == nil)
    }

    /// outdent moves a child right after its (former) parent; root tasks are
    /// unaffected.
    @Test("outdentStructuredTask moves a child right after its parent")
    func outdentMovesAfterParent() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let parent = TaskManager.createStructuredTask(title: "Parent", in: context) // root 0
        let child = TaskManager.createStructuredTask(title: "Child", parent: parent, in: context)
        let tail = TaskManager.createStructuredTask(title: "Tail", in: context) // root 1

        TaskManager.outdentStructuredTask(child, in: context)

        #expect(child.parent == nil)
        #expect(parent.structuredOrder == 0)
        #expect(child.structuredOrder == 1)
        #expect(tail.structuredOrder == 2)

        // Root task: no parent to step out of, so nothing changes.
        TaskManager.outdentStructuredTask(parent, in: context)
        #expect(parent.parent == nil)
        #expect(parent.structuredOrder == 0)
    }

    /// Moving a task into its own subtree (or itself) is rejected.
    @Test("moveStructuredTask rejects cycles (self and descendants)")
    func moveRejectsCycles() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let root = TaskManager.createStructuredTask(title: "Root", in: context)
        let child = TaskManager.createStructuredTask(title: "Child", parent: root, in: context)
        let grandchild = TaskManager.createStructuredTask(title: "Grandchild", parent: child, in: context)

        // Into its own grandchild: rejected, tree unchanged.
        TaskManager.moveStructuredTask(root, toParent: grandchild, in: context)
        #expect(root.parent == nil)
        #expect(grandchild.children.isEmpty)

        // Into itself: rejected as well.
        TaskManager.moveStructuredTask(child, toParent: child, in: context)
        #expect(child.parent?.id == root.id)
    }

    // MARK: - Search

    /// searchTasks matches titles case-insensitively and ignores empty queries.
    @Test("searchTasks matches case-insensitively and ignores empty queries")
    func searchMatchesTitles() throws {
        let container = try makeContainer()
        let context = container.mainContext

        TaskManager.createStructuredTask(title: "Write report", in: context)
        TaskManager.createStructuredTask(title: "Report bugs", in: context)
        TaskManager.createStructuredTask(title: "Buy milk", in: context)

        let hits = TaskManager.searchTasks(matching: "report", in: context)
        #expect(hits.count == 2)
        #expect(hits.allSatisfy { $0.title.localizedStandardContains("report") })

        #expect(TaskManager.searchTasks(matching: "   ", in: context).isEmpty)
    }

    /// searchTasks caps the number of results at the given limit.
    @Test("searchTasks caps results at the limit")
    func searchRespectsLimit() throws {
        let container = try makeContainer()
        let context = container.mainContext

        for index in 0..<5 {
            TaskManager.createStructuredTask(title: "Task \(index)", in: context)
        }

        let hits = TaskManager.searchTasks(matching: "Task", limit: 3, in: context)
        #expect(hits.count == 3)
    }
}
