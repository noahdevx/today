import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Structured area: hierarchical tree of all tasks organized as projects and
/// sub-tasks. Supports unlimited nesting, collapsible nodes, drag & drop both
/// to the Today column and within the tree (reorder / re-parent), and Today
/// state encoded in the row background. The header shows the grand total of
/// all task estimates.
///
/// The recursive node view lives in `StructuredNodeView.swift`; the drop
/// delegates in `StructuredDropDelegates.swift`.
struct StructuredAreaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SelectionEngine.self) private var selectionEngine
    @Environment(HoverLinkEngine.self) private var hoverEngine

    /// Every task in the store, sorted by structured position. Root tasks are
    /// filtered out by the computed property below. A single `@Query` keeps the
    /// view reactive to insertions, deletions, reorders, and state changes.
    @Query(sort: \TodayTask.structuredOrder) private var allTasks: [TodayTask]

    /// Draft fields for the root-level "add task" input.
    @State private var newTitle = ""
    @State private var newMinutes = ""
    /// True while a dragged task hovers over the root-tail drop area.
    @State private var isTailTargeted = false

    /// Root-level tasks (no parent) in structured order.
    private var rootTasks: [TodayTask] {
        allTasks.filter { $0.parent == nil }
    }

    /// Ancestor IDs of the task hovered or selected anywhere in the app.
    /// Injected into the tree so a collapsed node can stand in (highlighted)
    /// for a linked task hidden inside its subtree.
    private var linkedAncestorIDs: Set<UUID> {
        let linkedID = hoverEngine.hoveredTaskID ?? selectionEngine.selectedTaskID
        guard let linkedID,
              let task = allTasks.first(where: { $0.id == linkedID }) else { return [] }
        return Set(task.ancestors.map(\.id))
    }

    var body: some View {
        AreaColumn(
            title: "Structured",
            totalTime: allTasks.totalEstimateLabel,
            accent: .blue
        ) {
            VStack(alignment: .leading, spacing: 10) {
                addRootRow

                if rootTasks.isEmpty {
                    Text("No tasks yet. Add one above or drag from Today.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    treeContent
                }
            }
        }
        .environment(\.linkedAncestorIDs, linkedAncestorIDs)
    }

    // MARK: - Root task input

    /// Input row for creating a new root-level task in the structured tree.
    private var addRootRow: some View {
        HStack(spacing: 6) {
            TextField("Add a project or task", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addRootTask)
            TextField("min", text: $newMinutes)
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
                .onSubmit(addRootTask)
            Button(action: addRootTask) {
                Image(systemName: "plus")
            }
            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addRootTask() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let minutes = Int(newMinutes.trimmingCharacters(in: .whitespaces))
            .flatMap { $0 > 0 ? $0 : nil }
        TaskManager.createStructuredTask(
            title: title,
            estimatedMinutes: minutes,
            in: modelContext
        )
        newTitle = ""
        newMinutes = ""
    }

    // MARK: - Tree

    /// Scrollable tree of structured nodes, rendered recursively, with a
    /// trailing drop area that moves a dragged task to the end of the root
    /// level (so it can always be "un-nested" even when no row gap fits).
    /// A ScrollViewReader keeps the keyboard/search selection in view.
    private var treeContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rootTasks) { task in
                        StructuredNodeView(task: task, depth: 0)
                    }

                    // Root-tail drop area: visible insertion line while targeted.
                    Color.clear
                        .frame(height: 28)
                        .overlay(alignment: .top) {
                            if isTailTargeted {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                            }
                        }
                        .onDrop(
                            of: [.plainText],
                            delegate: StructuredRootTailDropDelegate(
                                engine: selectionEngine,
                                context: modelContext,
                                isTargeted: $isTailTargeted
                            )
                        )
                }
            }
            // Scroll requests target this tree on any selection (row clicks
            // in other areas included, so the Today <-> Structured link stays
            // visible), arrow-key moves, and search jumps. Ancestors were
            // already expanded by the engine in the same update, so the row
            // exists by the time this fires.
            .onChange(of: selectionEngine.scrollRequests) { _, requests in
                guard let target = requests.first(where: { $0.area == .structured }) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(target.taskID)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

#Preview {
    StructuredAreaView()
        .frame(width: 300, height: 500)
        .environment(HoverLinkEngine())
        .environment(SelectionEngine())
        .modelContainer(for: TodayTask.self, inMemory: true)
}
