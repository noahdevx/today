import Foundation
import SwiftData
import Testing
@testable import Today

/// Unit tests for `SelectionEngine` against a real (in-memory) SwiftData
/// store: visible-order computation, keyboard navigation, deletion flow,
/// escape handling, and search jumps. Runs on the main actor because the
/// engine and `mainContext` are main-actor isolated.
@MainActor
@Suite("SelectionEngine")
struct SelectionEngineTests {
    /// Fresh in-memory container per test. The caller keeps it in a local for
    /// the test's lifetime; releasing it would tear down the context mid-test.
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: TodayTask.self, configurations: configuration)
    }

    /// Today's visible order follows todayOrder.
    @Test("visibleTaskIDs(today) follows todayOrder")
    func visibleTodayOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = SelectionEngine()

        let first = TaskManager.addToToday(title: "First", in: context)
        let second = TaskManager.addToToday(title: "Second", in: context)

        #expect(engine.visibleTaskIDs(in: .today, context: context) == [first.id, second.id])
    }

    /// Structured visible order is a depth-first walk that skips collapsed
    /// subtrees.
    @Test("visibleTaskIDs(structured) walks depth-first and skips collapsed subtrees")
    func visibleStructuredOrderRespectsCollapse() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = SelectionEngine()

        let rootA = TaskManager.createStructuredTask(title: "A", in: context)
        let childA1 = TaskManager.createStructuredTask(title: "A1", parent: rootA, in: context)
        let grandA1a = TaskManager.createStructuredTask(title: "A1a", parent: childA1, in: context)
        let rootB = TaskManager.createStructuredTask(title: "B", in: context)

        // Fully expanded: DFS order.
        #expect(
            engine.visibleTaskIDs(in: .structured, context: context)
                == [rootA.id, childA1.id, grandA1a.id, rootB.id]
        )

        // Collapsing A hides its whole subtree.
        engine.toggleCollapsed(rootA.id)
        #expect(engine.visibleTaskIDs(in: .structured, context: context) == [rootA.id, rootB.id])
    }

    /// Arrow up/down moves within the area and stops at the edges.
    @Test("moveSelection steps through rows and stops at the ends")
    func moveSelectionSteps() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = SelectionEngine()

        let first = TaskManager.addToToday(title: "First", in: context)
        let second = TaskManager.addToToday(title: "Second", in: context)

        // No selection yet: down enters at the top.
        engine.focusedArea = .today
        engine.moveSelection(.down, context: context)
        #expect(engine.selectedTaskID == first.id)

        engine.moveSelection(.down, context: context)
        #expect(engine.selectedTaskID == second.id)

        // At the bottom: stays (no wrap).
        engine.moveSelection(.down, context: context)
        #expect(engine.selectedTaskID == second.id)

        engine.moveSelection(.up, context: context)
        #expect(engine.selectedTaskID == first.id)
    }

    /// Right arrow expands a collapsed node first, then steps into the first
    /// child on the next press (standard outline behavior).
    @Test("expandSelection expands a collapsed node then steps into children")
    func expandSelectionBehavior() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = SelectionEngine()

        let root = TaskManager.createStructuredTask(title: "Root", in: context)
        let child = TaskManager.createStructuredTask(title: "Child", parent: root, in: context)
        engine.toggleCollapsed(root.id)
        engine.select(root, in: .structured)

        // First press: expand; the selection stays on the node.
        engine.expandSelection(context: context)
        #expect(!engine.collapsedIDs.contains(root.id))
        #expect(engine.selectedTaskID == root.id)

        // Second press: step into the first child.
        engine.expandSelection(context: context)
        #expect(engine.selectedTaskID == child.id)
    }

    /// Left arrow climbs from a leaf to its parent, collapses an expanded
    /// node, and is a no-op on a collapsed root.
    @Test("collapseSelection collapses or climbs to the parent")
    func collapseSelectionBehavior() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = SelectionEngine()

        let root = TaskManager.createStructuredTask(title: "Root", in: context)
        let child = TaskManager.createStructuredTask(title: "Child", parent: root, in: context)
        engine.select(child, in: .structured)

        // Leaf: climb to the parent.
        engine.collapseSelection(context: context)
        #expect(engine.selectedTaskID == root.id)

        // Expanded parent: collapse it, selection stays.
        engine.collapseSelection(context: context)
        #expect(engine.collapsedIDs.contains(root.id))
        #expect(engine.selectedTaskID == root.id)

        // Collapsed root (no parent): nothing left to do.
        engine.collapseSelection(context: context)
        #expect(engine.selectedTaskID == root.id)
    }

    /// Tab indents the selection under its previous sibling and expands the
    /// new parent so the moved row stays visible.
    @Test("indentSelection nests under the previous sibling and reveals it")
    func indentSelectionNests() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = SelectionEngine()

        let first = TaskManager.createStructuredTask(title: "First", in: context)
        let second = TaskManager.createStructuredTask(title: "Second", in: context)
        engine.toggleCollapsed(first.id)
        engine.select(second, in: .structured)

        engine.indentSelection(context: context)

        #expect(second.parent?.id == first.id)
        // The new parent was expanded so the indented row stays visible.
        #expect(!engine.collapsedIDs.contains(first.id))
    }

    /// Deleting keeps the flow going by selecting the row that took the slot.
    @Test("deleteSelection removes the task and selects its successor")
    func deleteSelectsSuccessor() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = SelectionEngine()

        let first = TaskManager.addToToday(title: "First", in: context)
        let second = TaskManager.addToToday(title: "Second", in: context)

        engine.select(first, in: .today)
        engine.deleteSelection(context: context)

        #expect(TaskManager.findTask(id: first.id, in: context) == nil)
        #expect(engine.selectedTaskID == second.id)
    }

    /// Tab from the minutes editor advances to the next task's title editor
    /// and ends editing on the last row.
    @Test("editNextTask advances to the next row and ends on the last")
    func editNextTaskAdvances() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = SelectionEngine()

        let first = TaskManager.addToToday(title: "First", in: context)
        let second = TaskManager.addToToday(title: "Second", in: context)

        engine.select(first, in: .today)
        engine.editingField = .minutes
        engine.editNextTask(context: context)
        #expect(engine.selectedTaskID == second.id)
        #expect(engine.editingField == .title)

        // On the last row, Tab simply ends editing.
        engine.editingField = .minutes
        engine.editNextTask(context: context)
        #expect(engine.editingField == nil)
    }

    /// Escape cancels editing first, then clears the selection, then is no
    /// longer consumed (so the panel can hide).
    @Test("handleEscape steps through editing, selection, then passes through")
    func escapeTwoStage() throws {
        let engine = SelectionEngine()
        engine.focusedArea = .today
        engine.selectedTaskID = UUID()
        engine.editingField = .title

        #expect(engine.handleEscape())
        #expect(engine.editingField == nil)
        #expect(engine.selectedTaskID != nil)

        #expect(engine.handleEscape())
        #expect(engine.selectedTaskID == nil)

        #expect(!engine.handleEscape())
    }

    /// Jumping to a search result expands collapsed ancestors, focuses the
    /// task's home area, and selects it.
    @Test("jump reveals collapsed ancestors and selects the task")
    func jumpRevealsAndSelects() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = SelectionEngine()

        let root = TaskManager.createStructuredTask(title: "Root", in: context)
        let child = TaskManager.createStructuredTask(title: "Child", parent: root, in: context)
        engine.toggleCollapsed(root.id)
        #expect(engine.collapsedIDs.contains(root.id))

        engine.jump(to: child)

        #expect(!engine.collapsedIDs.contains(root.id))
        #expect(engine.focusedArea == .structured)
        #expect(engine.selectedTaskID == child.id)
    }

    /// Selecting a task in any area reveals it in the structured tree:
    /// collapsed ancestors expand and a structured scroll request is queued.
    @Test("select reveals the task in the structured tree and requests a scroll")
    func selectRevealsInStructured() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = SelectionEngine()

        // A nested task that is also in Today, hidden under a collapsed parent.
        let parent = TaskManager.createStructuredTask(title: "Parent", in: context)
        let child = TaskManager.createStructuredTask(title: "Child", parent: parent, in: context)
        TaskManager.addStructuredTaskToToday(child, in: context)
        engine.toggleCollapsed(parent.id)

        // Clicking the task's row in the Today column...
        engine.select(child, in: .today)

        // ...expands the collapsed parent and asks the tree to scroll to it.
        #expect(!engine.collapsedIDs.contains(parent.id))
        #expect(engine.scrollRequests.contains { $0.area == .structured && $0.taskID == child.id })
    }

    /// A search jump scrolls both the home area's list and the structured
    /// tree; repeated jumps to the same task produce distinct requests.
    @Test("jump requests scrolls in the home area and the structured tree")
    func jumpRequestsScrolls() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = SelectionEngine()

        let task = TaskManager.addToToday(title: "T", in: context)
        engine.jump(to: task)

        #expect(engine.scrollRequests.contains { $0.area == .today && $0.taskID == task.id })
        #expect(engine.scrollRequests.contains { $0.area == .structured && $0.taskID == task.id })

        // Jumping again must change the request value (new generation) so
        // observers fire even for the same task.
        let firstBatch = engine.scrollRequests
        engine.jump(to: task)
        #expect(engine.scrollRequests != firstBatch)
    }

    /// homeArea mirrors the area queries' membership rules.
    @Test("homeArea picks the most specific area for a task")
    func homeAreaRules() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = SelectionEngine()

        let today = TaskManager.addToToday(title: "T", in: context)
        let structured = TaskManager.createStructuredTask(title: "S", in: context)
        let scheduled = TaskManager.schedule(title: "Sch", at: .now, in: context)
        let waiting = TaskManager.startWaiting(title: "W", in: context)
        let done = TaskManager.addToToday(title: "D", in: context)
        TaskManager.complete(done, in: context)

        #expect(engine.homeArea(of: today) == .today)
        #expect(engine.homeArea(of: structured) == .structured)
        #expect(engine.homeArea(of: scheduled) == .scheduled)
        #expect(engine.homeArea(of: waiting) == .waiting)
        #expect(engine.homeArea(of: done) == .done)
    }
}
