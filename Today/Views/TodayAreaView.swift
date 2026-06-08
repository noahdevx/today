import SwiftData
import SwiftUI

/// Today area (left-most column): cross-project, single-column ordering of what to
/// tackle today. Backed by SwiftData -- tasks are added, reordered by dragging,
/// completed, and deleted here -- and the header shows the live total estimate.
struct TodayAreaView: View {
    /// Bound to the parent so the header's Done button shows/hides the Done column.
    @Binding var showDone: Bool

    /// The shared context for all mutations (injected via `.modelContainer`).
    @Environment(\.modelContext) private var modelContext
    /// Hover engine for the Today → Structured/Map highlight link.
    @Environment(HoverLinkEngine.self) private var hoverEngine

    /// Active Today tasks: placed in Today (`todayOrder != nil`) and not yet done,
    /// sorted by their Today position. The query updates automatically on changes.
    @Query(
        filter: #Predicate<TodayTask> { $0.todayOrder != nil && $0.doneAt == nil },
        sort: \TodayTask.todayOrder
    )
    private var tasks: [TodayTask]

    /// Draft title for the new-task field.
    @State private var newTitle = ""
    /// Draft estimate (minutes) for the new-task field; empty means "no estimate".
    @State private var newMinutes = ""
    /// True while a dragged item hovers over this column (visual drop feedback).
    @State private var isDropTargeted = false

    var body: some View {
        AreaColumn(title: "Today", totalTime: tasks.totalEstimateLabel, accent: .yellow) {
            VStack(alignment: .leading, spacing: 10) {
                doneToggle
                addRow
                taskList
            }
        }
        // Visual feedback: highlight the column border when a structured task
        // is dragged over it.
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(0.5), lineWidth: 2)
            }
        }
        // Accept drops of structured task IDs (UUID strings).
        .dropDestination(for: String.self) { items, _ in
            handleExternalDrop(items)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    // MARK: - Subviews

    /// Button that toggles the Done column; the icon reflects open/closed state.
    private var doneToggle: some View {
        Button {
            showDone.toggle()
        } label: {
            Label("Done", systemImage: showDone ? "chevron.left" : "checkmark.circle")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// New-task input: a title field plus an optional minutes field. Submitting
    /// either field, or pressing the add button, creates the task.
    private var addRow: some View {
        HStack(spacing: 6) {
            TextField("Add a task", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addTask)
            TextField("min", text: $newMinutes)
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
                .onSubmit(addTask)
            Button(action: addTask) {
                Image(systemName: "plus")
            }
            // Disabled until there's a non-empty title to add.
            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// The ordered, drag-reorderable list of today's tasks. `.onMove` enables the
    /// native drag handle; swiping a row reveals Delete.
    private var taskList: some View {
        List {
            ForEach(tasks) { task in
                TaskRow(task: task) {
                    TaskManager.complete(task, in: modelContext)
                }
                // Update the hover engine so Structured and Map highlight this task.
                .onHover { hovering in
                    hoverEngine.hoveredTaskID = hovering ? task.id : nil
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        TaskManager.delete(task, in: modelContext)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove(perform: moveTasks)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Let the list fill the remaining column height.
        .frame(maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Validates and creates a task from the draft fields, then clears them. A
    /// non-positive minutes value is treated as "no estimate".
    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let minutes = Int(newMinutes.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
        TaskManager.addToToday(title: title, estimatedMinutes: minutes, in: modelContext)
        newTitle = ""
        newMinutes = ""
    }

    /// Forwards a drag-reorder to the manager, which renumbers `todayOrder`.
    private func moveTasks(from source: IndexSet, to destination: Int) {
        TaskManager.reorderToday(tasks, from: source, to: destination, in: modelContext)
    }

    /// Handles a drop of structured task IDs (UUID strings) into the Today
    /// column. Each task is looked up by ID and added to Today if it isn't
    /// there already.
    private func handleExternalDrop(_ items: [String]) -> Bool {
        var handled = false
        for item in items {
            guard let uuid = UUID(uuidString: item),
                  let task = TaskManager.findTask(id: uuid, in: modelContext) else { continue }
            TaskManager.addStructuredTaskToToday(task, in: modelContext)
            handled = true
        }
        return handled
    }
}
