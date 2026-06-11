import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A single node in the structured tree. Renders its own row and recursively
/// renders sorted children. Supports collapsing (state lives in
/// SelectionEngine so navigation/search can reach it), dragging to Today or
/// within the tree, 3-zone drops (insert above / nest inside / insert below),
/// context-menu actions, and inline sub-task creation.
struct StructuredNodeView: View {
    let task: TodayTask
    let depth: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(HoverLinkEngine.self) private var hoverEngine
    @Environment(SelectionEngine.self) private var selectionEngine
    /// The Now task's ID (head of the Today column), for the yellow treatment.
    @Environment(\.nowTaskID) private var nowTaskID
    /// Current appearance, used to pick a "white-ish" Today background that
    /// also reads correctly in dark mode.
    @Environment(\.colorScheme) private var colorScheme

    @State private var isAddingChild = false
    @State private var newChildTitle = ""
    @State private var newChildMinutes = ""
    /// The drop zone currently hovered by an in-flight drag, for the
    /// insertion-line / nesting feedback. Nil when no drag is over this row.
    @State private var hoverZone: StructuredDropZone?
    /// Measured row height, used by the drop delegate's 3-zone split.
    @State private var rowHeight: CGFloat = 0

    /// Whether this node's children are visible. The backing set lives in
    /// SelectionEngine so keyboard navigation and search jumps can read and
    /// change what is actually expanded.
    private var isExpanded: Bool {
        !selectionEngine.collapsedIDs.contains(task.id)
    }

    /// Whether the Today hover engine is highlighting this node right now.
    private var isHighlighted: Bool {
        hoverEngine.hoveredTaskID == task.id
    }

    /// Whether this node is the Now task (the head of the Today column).
    private var isNow: Bool {
        nowTaskID == task.id && !task.isDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nodeRow
                .padding(.vertical, 4)
                .padding(.leading, CGFloat(depth) * 16 + 4)
                .padding(.trailing, 4)
                .background(rowBackground)
                .contentShape(Rectangle())
                // Track the row's height for the drop delegate's zone split.
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { rowHeight = geometry.size.height }
                            .onChange(of: geometry.size.height) { _, newHeight in
                                rowHeight = newHeight
                            }
                    }
                }
                // Drop feedback: insertion lines for before/after, an accent
                // ring for "nest inside".
                .overlay(alignment: .top) {
                    if hoverZone == .before { insertionLine }
                }
                .overlay(alignment: .bottom) {
                    if hoverZone == .after { insertionLine }
                }
                .overlay {
                    if hoverZone == .child {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }
                // Drag source: records the dragged task in the engine (for
                // synchronous validation in drop targets) and vends the UUID
                // as plain text for the actual transfer.
                .onDrag {
                    selectionEngine.draggedTaskID = task.id
                    return NSItemProvider(object: task.id.uuidString as NSString)
                }
                // Drop target: 3-zone tree move (above / inside / below).
                .onDrop(
                    of: [.plainText],
                    delegate: StructuredRowDropDelegate(
                        target: task,
                        rowHeight: rowHeight,
                        engine: selectionEngine,
                        context: modelContext,
                        hoverZone: $hoverZone
                    )
                )
                // Click to select; accent ring while selected.
                .taskSelectable(task, in: .structured)
                .contextMenu { nodeContextMenu }
                // Anchor for ScrollViewReader (selection follow / search jump).
                .id(task.id)

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

    /// The 2pt accent line shown at the edge a drag would insert at.
    private var insertionLine: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.leading, CGFloat(depth) * 16 + 4)
    }

    // MARK: - Row content

    /// The horizontal row: disclosure toggle, done marker, then either the
    /// static title + time labels or the inline editor while editing.
    private var nodeRow: some View {
        HStack(spacing: 6) {
            disclosureToggle
            todayMarker
            if selectionEngine.isEditing(task.id, in: .structured) {
                InlineTaskEditor(task: task, area: .structured)
            } else {
                titleLabel

                Spacer(minLength: 4)

                timeLabel
            }
        }
    }

    /// Chevron toggle for expanding/collapsing children. Invisible spacer for
    /// leaf nodes to keep titles aligned.
    @ViewBuilder
    private var disclosureToggle: some View {
        if !task.children.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectionEngine.toggleCollapsed(task.id)
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

    /// Visual marker for completed tasks (Today membership is now expressed by
    /// the row background instead of a dot). Always occupies a fixed width so
    /// the title doesn't shift when the marker appears or disappears.
    private var todayMarker: some View {
        Group {
            if task.isDone {
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

    /// Background encoding the task's Today state, per the design spec:
    /// hover highlight wins, then yellow for the Now task, then a white-ish
    /// tint for the other Today-linked tasks.
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(backgroundFill)
    }

    private var backgroundFill: Color {
        if isHighlighted {
            return .yellow.opacity(0.2)
        }
        if isNow {
            // Now task: the one being worked on right now.
            return .yellow.opacity(0.35)
        }
        if task.isInToday && !task.isDone {
            // Today-linked (but not Now): white in light mode, a light surface
            // tint in dark mode where pure white would glare.
            return colorScheme == .dark ? Color.white.opacity(0.12) : Color.white
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
            // Make sure the new child will be visible.
            selectionEngine.collapsedIDs.remove(task.id)
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
