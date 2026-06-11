import SwiftData
import SwiftUI

/// Minimap of the Structured area. Draws a condensed, non-interactive tree of
/// colored bars and highlights the node currently hovered in the Today column.
/// Acts as a visual anchor so the user can locate the hovered task's position
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
/// node. Bar color encodes state: yellow for the hovered node, blue for
/// Today-linked tasks, grey for completed ones, and a neutral tone for others.
private struct MinimapNode: View {
    let task: TodayTask
    let depth: Int
    @Environment(HoverLinkEngine.self) private var hoverEngine

    /// Whether the Today hover engine is targeting this exact node.
    private var isHighlighted: Bool {
        hoverEngine.hoveredTaskID == task.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(barColor)
                .frame(height: isHighlighted ? 6 : 4)
                .padding(.leading, CGFloat(depth) * 6)

            ForEach(task.sortedChildren) { child in
                MinimapNode(task: child, depth: depth + 1)
            }
        }
    }

    /// Bar color derived from the task's state and hover status.
    private var barColor: Color {
        if isHighlighted { return .yellow }
        if task.isInToday && !task.isDone { return .blue.opacity(0.6) }
        if task.isDone { return .gray.opacity(0.3) }
        return .secondary.opacity(0.25)
    }
}

#Preview {
    MinimapView()
        .frame(width: 96, height: 500)
        .environment(HoverLinkEngine())
        .modelContainer(for: TodayTask.self, inMemory: true)
}
