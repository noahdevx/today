import Foundation
import SwiftData
import Testing
@testable import Today

/// Integration tests that exercise `TodayTask` against a real (in-memory)
/// SwiftData store: persistence, the parent/children relationship, and the
/// cascade delete rule. Runs on the main actor because `mainContext` is
/// main-actor isolated.
@MainActor
@Suite("TodayTask persistence")
struct TodayTaskPersistenceTests {
    /// Creates a fresh in-memory container. The caller keeps the returned
    /// container in a local for the test's lifetime; if it were released the
    /// context would be torn down mid-test.
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: TodayTask.self, configurations: configuration)
    }

    /// B3: inserting a task and fetching returns exactly that task.
    @Test("inserting a task then fetching returns exactly that task")
    func insertThenFetch() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let task = TodayTask(title: "Buy milk")
        context.insert(task)

        let fetched = try context.fetch(FetchDescriptor<TodayTask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Buy milk")
        #expect(fetched.first?.id == task.id)
    }

    /// B4: assigning `child.parent` wires both sides of the relationship.
    @Test("assigning a child wires both sides of the relationship")
    func relationshipWiring() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let parent = TodayTask(title: "Project")
        let child = TodayTask(title: "Subtask")
        context.insert(parent)
        context.insert(child)
        child.parent = parent
        try context.save()

        #expect(child.parent?.id == parent.id)
        #expect(parent.children.contains { $0.id == child.id })
    }

    /// B5: deleting a parent cascades to its children (deleteRule .cascade).
    @Test("deleting a parent cascades to its children")
    func cascadeDelete() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let parent = TodayTask(title: "Project")
        let childA = TodayTask(title: "A")
        let childB = TodayTask(title: "B")
        context.insert(parent)
        context.insert(childA)
        context.insert(childB)
        childA.parent = parent
        childB.parent = parent
        try context.save()
        #expect(try context.fetch(FetchDescriptor<TodayTask>()).count == 3)

        context.delete(parent)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<TodayTask>()).isEmpty)
    }

    // MARK: - Subtree time aggregation

    /// A leaf task's subtree total equals its own estimate.
    @Test("subtreeEstimatedMinutes for a leaf equals its own estimate")
    func subtreeLeaf() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let leaf = TodayTask(title: "Leaf", estimatedMinutes: 30)
        context.insert(leaf)
        try context.save()

        #expect(leaf.subtreeEstimatedMinutes == 30)
    }

    /// A parent's subtree total includes its own estimate plus all descendants.
    @Test("subtreeEstimatedMinutes sums the entire subtree recursively")
    func subtreeRecursive() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let root = TodayTask(title: "Root", estimatedMinutes: 10)
        let childA = TodayTask(title: "A", estimatedMinutes: 20)
        let childB = TodayTask(title: "B", estimatedMinutes: 30)
        let grandchild = TodayTask(title: "A1", estimatedMinutes: 40)
        context.insert(root)
        context.insert(childA)
        context.insert(childB)
        context.insert(grandchild)
        childA.parent = root
        childB.parent = root
        grandchild.parent = childA
        try context.save()

        #expect(root.subtreeEstimatedMinutes == 100)
        #expect(childA.subtreeEstimatedMinutes == 60)
        #expect(childB.subtreeEstimatedMinutes == 30)
    }

    /// Unestimated tasks contribute zero to the subtree total.
    @Test("subtreeEstimatedMinutes treats unestimated tasks as zero")
    func subtreeUnestimated() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let root = TodayTask(title: "Root")
        let child = TodayTask(title: "Child", estimatedMinutes: 15)
        context.insert(root)
        context.insert(child)
        child.parent = root
        try context.save()

        #expect(root.subtreeEstimatedMinutes == 15)
        #expect(root.subtreeEstimateLabel == "15m")
    }

    /// sortedChildren returns children in structuredOrder.
    @Test("sortedChildren returns children ordered by structuredOrder")
    func sortedChildrenOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let parent = TodayTask(title: "Parent")
        let childC = TodayTask(title: "C", structuredOrder: 2)
        let childA = TodayTask(title: "A", structuredOrder: 0)
        let childB = TodayTask(title: "B", structuredOrder: 1)
        context.insert(parent)
        context.insert(childC)
        context.insert(childA)
        context.insert(childB)
        childA.parent = parent
        childB.parent = parent
        childC.parent = parent
        try context.save()

        let sorted = parent.sortedChildren
        #expect(sorted.map(\.title) == ["A", "B", "C"])
    }
}
