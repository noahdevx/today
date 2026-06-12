import SwiftData
import SwiftUI

/// Minimap of the Structured area. Draws a condensed, non-interactive tree of
/// colored bars and highlights the task currently hovered or selected in any
/// area. Acts as a visual anchor so the user can locate that task's position
/// in the overall project hierarchy without scrolling the Structured column.
struct MinimapView: View {
    /// All tasks for the condensed tree. Root nodes are filtered by the computed
    /// property below.
    @Query(sort: \TodayTask.structuredOrder) private var allTasks: [TodayTask]
    @Environment(HoverLinkEngine.self) private var hoverEngine

    /// Root-level tasks for the minimap tree.
    private var rootTasks: [TodayTask] {
        allTasks.filter { $0.parent == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Map")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            if rootTasks.isEmpty {
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(rootTasks) { task in
                            MinimapNode(task: task, depth: 0)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Minimap node (recursive)

/// A single condensed bar in the minimap, rendered recursively for each tree
/// node. Bar color encodes state: accent (and a taller bar) for the task
/// hovered/selected anywhere, blue for Today-linked tasks, grey for completed
/// ones, and a neutral tone for others.
///
/// The bars participate in the cross-area link in both directions: hovering a
/// bar highlights the task's rows in the other areas, and clicking a bar
/// reveals the task in the structured tree and scrolls it into view (like a
/// code editor's minimap).
private struct MinimapNode: View {
    let task: TodayTask
    let depth: Int
    @Environment(HoverLinkEngine.self) private var hoverEngine
    @Environment(SelectionEngine.self) private var selectionEngine

    /// Whether this task is the current link-highlight target (the same
    /// hover-over-focus exclusivity the row highlight uses: the hovered task
    /// while hovering, otherwise the selected one).
    private var isHighlighted: Bool {
        if let hoveredID = hoverEngine.hoveredTaskID {
            return hoveredID == task.id
        }
        return selectionEngine.selectedTaskID == task.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(barColor)
                .frame(height: isHighlighted ? 6 : 4)
                .padding(.leading, CGFloat(depth) * 6)
                // Make the full bar width (thin as it is) hit-testable.
                .contentShape(Rectangle())
                // Hovering a bar highlights the task everywhere else. Only
                // clear the shared state if this bar still owns it (the next
                // bar's "enter" can arrive before this one's "exit").
                .onHover { hovering in
                    if hovering {
                        hoverEngine.hoveredTaskID = task.id
                    } else if hoverEngine.hoveredTaskID == task.id {
                        hoverEngine.hoveredTaskID = nil
                    }
                }
                // Clicking jumps the structured tree to this task (expanding
                // collapsed ancestors), without changing the selection.
                .onTapGesture {
                    selectionEngine.revealAndScrollInStructured(task)
                }

            ForEach(task.sortedChildren) { child in
                MinimapNode(task: child, depth: depth + 1)
            }
        }
    }

    /// Bar color derived from the task's state and link-highlight status.
    /// The highlight uses the accent color (full opacity + taller bar) so it
    /// matches the row highlight while staying distinguishable from the
    /// dimmer Today bars.
    private var barColor: Color {
        if isHighlighted { return .accentColor }
        if task.isInToday && !task.isDone { return .blue.opacity(0.6) }
        if task.isDone { return .gray.opacity(0.3) }
        return .secondary.opacity(0.25)
    }
}

#Preview {
    MinimapView()
        .frame(width: 96, height: 500)
        .environment(HoverLinkEngine())
        .environment(SelectionEngine())
        .modelContainer(for: TodayTask.self, inMemory: true)
}
