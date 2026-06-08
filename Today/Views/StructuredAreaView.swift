import SwiftData
import SwiftUI

/// Structured area: hierarchical tree of all tasks organized as projects and
/// sub-tasks. Supports unlimited nesting, collapsible nodes, dragging tasks to
/// the Today column, and visual markers for Today-linked tasks. The header shows
/// the grand total of all task estimates.
struct StructuredAreaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HoverLinkEngine.self) private var hoverEngine

    /// Every task in the store, sorted by structured position. Root tasks are
    /// filtered out by the computed property below. A single `@Query` keeps the
    /// view reactive to insertions, deletions, reorders, and state changes.
    @Query(sort: \TodayTask.structuredOrder) private var allTasks: [TodayTask]

    /// Draft fields for the root-level "add task" input.
    @State private var newTitle = ""
    @State private var newMinutes = ""

    /// Root-level tasks (no parent) in structured order.
    private var rootTasks: [TodayTask] {
        allTasks.filter { $0.parent == nil }
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

    /// Scrollable tree of structured nodes, rendered recursively.
    private var treeContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rootTasks) { task in
                    StructuredNodeView(task: task, depth: 0)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Tree node (recursive)

/// A single node in the structured tree. Renders its own row and recursively
/// renders sorted children. Supports collapsing, drag-to-Today, context-menu
/// actions, and inline sub-task creation.
struct StructuredNodeView: View {
    let task: TodayTask
    let depth: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(HoverLinkEngine.self) private var hoverEngine

    @State private var isExpanded = true
    @State private var isAddingChild = false
    @State private var newChildTitle = ""
    @State private var newChildMinutes = ""

    /// Whether the Today hover engine is highlighting this node right now.
    private var isHighlighted: Bool {
        hoverEngine.hoveredTaskID == task.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nodeRow
                .padding(.vertical, 4)
                .padding(.leading, CGFloat(depth) * 16 + 4)
                .padding(.trailing, 4)
                .background(rowBackground)
                .contentShape(Rectangle())
                .draggable(task.id.uuidString)
                .contextMenu { nodeContextMenu }

            if isAddingChild {
                addChildRow
                    .padding(.leading, CGFloat(depth + 1) * 16 + 4)
                    .padding(.trailing, 4)
                    .padding(.vertical, 4)
            }

            if isExpanded {
                ForEach(task.sortedChildren) { child in
                    StructuredNodeView(task: child, depth: depth + 1)
                }
            }
        }
    }

    // MARK: - Row content

    /// The horizontal row: disclosure toggle, Today marker, title, time label.
    private var nodeRow: some View {
        HStack(spacing: 6) {
            disclosureToggle
            todayMarker
            titleLabel

            Spacer(minLength: 4)

            timeLabel
        }
    }

    /// Chevron toggle for expanding/collapsing children. Invisible spacer for
    /// leaf nodes to keep titles aligned.
    @ViewBuilder
    private var disclosureToggle: some View {
        if !task.children.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
        } else {
            Spacer()
                .frame(width: 12)
        }
    }

    /// Visual marker indicating the task's relationship to the Today / Done areas.
    /// Always occupies a fixed width so the title doesn't shift when the marker
    /// appears or disappears.
    private var todayMarker: some View {
        Group {
            if task.isInToday && !task.isDone {
                Circle()
                    .fill(.yellow)
                    .frame(width: 6, height: 6)
            } else if task.isDone {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Color.clear
            }
        }
        .frame(width: 10)
    }

    /// Task title, dimmed when the task is completed.
    private var titleLabel: some View {
        Text(task.title)
            .lineLimit(1)
            .foregroundStyle(task.isDone ? .secondary : .primary)
    }

    /// Time label: subtree total for nodes with children, own estimate for leaves.
    /// Hidden when a leaf has no estimate.
    @ViewBuilder
    private var timeLabel: some View {
        if !task.children.isEmpty {
            Text(task.subtreeEstimateLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        } else if let label = task.estimateLabel {
            Text(label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// Background that glows when highlighted by the Today hover engine and
    /// subtly tinted when the task is in Today.
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(backgroundFill)
    }

    private var backgroundFill: Color {
        if isHighlighted {
            return .yellow.opacity(0.2)
        }
        if task.isInToday && !task.isDone {
            return .yellow.opacity(0.06)
        }
        return .clear
    }

    // MARK: - Context menu

    @ViewBuilder
    private var nodeContextMenu: some View {
        if !task.isInToday || task.isDone {
            Button("Add to Today") {
                TaskManager.addStructuredTaskToToday(task, in: modelContext)
            }
        }
        if task.isInToday && !task.isDone {
            Button("Remove from Today") {
                TaskManager.removeFromToday(task, in: modelContext)
            }
        }

        Divider()

        Button("Add Sub-task") {
            isAddingChild = true
            isExpanded = true
        }

        Divider()

        Button("Delete", role: .destructive) {
            TaskManager.delete(task, in: modelContext)
        }
    }

    // MARK: - Inline sub-task creation

    /// Input row that appears below the node when the user chooses "Add Sub-task".
    private var addChildRow: some View {
        HStack(spacing: 6) {
            TextField("Sub-task title", text: $newChildTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addChild)
            TextField("min", text: $newChildMinutes)
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
                .onSubmit(addChild)
            Button(action: addChild) {
                Image(systemName: "plus")
            }
            .disabled(newChildTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            Button {
                isAddingChild = false
                newChildTitle = ""
                newChildMinutes = ""
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
    }

    private func addChild() {
        let title = newChildTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let minutes = Int(newChildMinutes.trimmingCharacters(in: .whitespaces))
            .flatMap { $0 > 0 ? $0 : nil }
        TaskManager.createStructuredTask(
            title: title,
            estimatedMinutes: minutes,
            parent: task,
            in: modelContext
        )
        newChildTitle = ""
        newChildMinutes = ""
        isAddingChild = false
    }
}

#Preview {
    StructuredAreaView()
        .frame(width: 300, height: 500)
        .environment(HoverLinkEngine())
        .modelContainer(for: TodayTask.self, inMemory: true)
}
