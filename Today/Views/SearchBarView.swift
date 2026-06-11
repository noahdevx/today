import SwiftData
import SwiftUI

/// Search field with a dropdown of matching tasks, hosted in the panel's top
/// bar. Cmd-F focuses the field; typing shows live results (title match,
/// case-insensitive) with an area badge and, for nested tasks, the parent
/// path. Up/down + Enter (or a click) jumps to a result: the selection
/// engine focuses the task's home area, expands collapsed ancestors, opens
/// the Done column when needed, and selects the task. Escape clears and
/// closes the search.
struct SearchBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SelectionEngine.self) private var selectionEngine

    /// Current query text (drives the dropdown).
    @State private var query = ""
    /// Index of the keyboard-highlighted dropdown row.
    @State private var highlightedIndex = 0
    /// Whether the search field has keyboard focus.
    @FocusState private var isFocused: Bool

    /// Live results for the current query (empty query = no results).
    private var results: [TodayTask] {
        TaskManager.searchTasks(matching: query, in: modelContext)
    }

    /// The dropdown shows while the field is focused and has matches.
    private var showsDropdown: Bool {
        isFocused && !results.isEmpty
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Search tasks", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isFocused)
                // Enter: jump to the highlighted result.
                .onSubmit(jumpToHighlighted)
                // Arrow keys move the dropdown highlight (not the caret).
                .onKeyPress(.downArrow) {
                    guard showsDropdown else { return .ignored }
                    highlightedIndex = min(highlightedIndex + 1, results.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard showsDropdown else { return .ignored }
                    highlightedIndex = max(highlightedIndex - 1, 0)
                    return .handled
                }
                // Escape: clear and leave the search field.
                .onKeyPress(.escape) {
                    guard isFocused else { return .ignored }
                    dismiss()
                    return .handled
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .frame(width: 220)
        // Reset the keyboard highlight whenever the result set changes.
        .onChange(of: query) {
            highlightedIndex = 0
        }
        // Cmd-F focuses the search field. The invisible button keeps the
        // shortcut active without rendering anything.
        .background {
            Button("Search") { isFocused = true }
                .keyboardShortcut("f")
                .opacity(0)
        }
        // Dropdown anchored right below the field, above the columns.
        .overlay(alignment: .topLeading) {
            if showsDropdown {
                dropdown
                    .offset(y: 26)
            }
        }
    }

    // MARK: - Dropdown

    /// The results list. Plain VStack (results are capped at 20) inside a
    /// scroll view, drawn on a raised background so it floats over the panel.
    private var dropdown: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, task in
                    SearchResultRow(
                        task: task,
                        area: selectionEngine.homeArea(of: task),
                        isHighlighted: index == highlightedIndex
                    )
                    .onTapGesture { jump(to: task) }
                    // Hovering with the mouse moves the keyboard highlight,
                    // like menu items.
                    .onHover { hovering in
                        if hovering { highlightedIndex = index }
                    }
                }
            }
            .padding(4)
        }
        .frame(width: 300)
        .frame(maxHeight: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
                .shadow(radius: 8, y: 2)
        )
    }

    // MARK: - Actions

    /// Jumps to the row highlighted by the arrow keys (Enter).
    private func jumpToHighlighted() {
        guard showsDropdown, results.indices.contains(highlightedIndex) else { return }
        jump(to: results[highlightedIndex])
    }

    /// Hands the task to the selection engine (reveal + focus + select) and
    /// closes the search.
    private func jump(to task: TodayTask) {
        selectionEngine.jump(to: task)
        dismiss()
    }

    /// Clears the query and gives up keyboard focus.
    private func dismiss() {
        query = ""
        isFocused = false
    }
}

// MARK: - Result row

/// One dropdown row: task title, the area it lives in (badge), and the parent
/// path for nested structured tasks.
private struct SearchResultRow: View {
    let task: TodayTask
    /// The task's home area, shown as a trailing badge.
    let area: AreaKind
    /// Whether this row is highlighted (keyboard or hover).
    let isHighlighted: Bool

    /// "Parent > Grandparent"-style breadcrumb, root first. Empty for root
    /// tasks, hidden in that case.
    private var parentPath: String {
        task.ancestors.reversed().map(\.title).joined(separator: " > ")
    }

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .lineLimit(1)
                if !parentPath.isEmpty {
                    Text(parentPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Area badge so the user knows where the jump will land.
            Text(area.badgeLabel)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHighlighted ? Color.accentColor.opacity(0.2) : .clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Area badge labels

extension AreaKind {
    /// Short, user-facing label for search-result badges.
    var badgeLabel: String {
        switch self {
        case .today: "Today"
        case .done: "Done"
        case .structured: "Structured"
        case .scheduled: "Scheduled"
        case .waiting: "Waiting"
        }
    }
}

#Preview {
    SearchBarView()
        .padding(40)
        .environment(SelectionEngine())
        .modelContainer(for: TodayTask.self, inMemory: true)
}
