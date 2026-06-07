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
}
