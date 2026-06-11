import SwiftData
import SwiftUI

/// Done area (toggled column between Today and Structured). Lists the tasks
/// completed today, shows the total time completed in its header, and lets a task
/// be restored to Today via its leading checkmark.
struct DoneAreaView: View {
    /// Shared context for mutations.
    @Environment(\.modelContext) private var modelContext
    /// Selection engine for row selection and inline editing.
    @Environment(SelectionEngine.self) private var selectionEngine

    /// Tasks completed today (`doneAt` on or after the start of today), most recent
    /// first. The "today" boundary is captured when the view initializes.
    @Query private var doneTasks: [TodayTask]

    init() {
        // Compute today's start now and bake it into the predicate: SwiftData can't
        // call `Calendar` inside a predicate, so the bound is captured here.
        let startOfToday = Calendar.current.startOfDay(for: .now)
        _doneTasks = Query(
            filter: #Predicate<TodayTask> { task in
                if let doneAt = task.doneAt {
                    return doneAt >= startOfToday
                } else {
                    return false
                }
            },
            sort: \TodayTask.doneAt,
            order: .reverse
        )
    }

    var body: some View {
        // Grey accent signals "completed / de-emphasized" per the design; the header
        // total is the sum of today's completed estimates.
        AreaColumn(title: "Done", totalTime: doneTasks.totalEstimateLabel, accent: .gray) {
            if doneTasks.isEmpty {
                // Empty state so the column reads clearly before anything is done.
                Text("Nothing completed yet today.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(doneTasks) { task in
                            // Static row (filled checkmark restores to Today) or
                            // the inline editor while the task is being edited.
                            Group {
                                if selectionEngine.isEditing(task.id, in: .done) {
                                    InlineTaskEditor(task: task, area: .done)
                                } else {
                                    TaskRow(task: task, systemImage: "checkmark.circle.fill") {
                                        TaskManager.restoreToToday(task, in: modelContext)
                                    }
                                }
                            }
                            .taskSelectable(task, in: .done)
                            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    TaskManager.delete(task, in: modelContext)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            // Anchor for ScrollViewReader (selection follow).
                            .id(task.id)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    // Follow the selection so the selected row stays visible.
                    .onChange(of: selectionEngine.selectedTaskID) { _, newID in
                        guard selectionEngine.focusedArea == .done, let newID else { return }
                        proxy.scrollTo(newID)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}
