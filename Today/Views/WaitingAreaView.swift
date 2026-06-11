import SwiftData
import SwiftUI

/// Waiting area (right-most column). Two stacked sections:
/// - Scheduled (top): tasks with a `scheduledAt` time. When the time arrives
///   the row turns red, prompting the user to move the task to Today.
/// - Waiting (bottom): tasks blocked on an external condition, with an
///   optional note. The user manually marks the condition cleared, which
///   moves the task to Today.
struct WaitingAreaView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Each section takes half of the column height.
            ScheduledSectionView()
                .frame(maxHeight: .infinity)

            Divider()

            WaitingSectionView()
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Scheduled section

/// Top section: time-triggered tasks ordered by their scheduled time. Wrapped
/// in a per-minute `TimelineView` so rows turn red when their time arrives
/// even while the panel stays open with no interaction.
private struct ScheduledSectionView: View {
    /// Shared context for mutations.
    @Environment(\.modelContext) private var modelContext
    /// Selection engine for row selection and inline editing.
    @Environment(SelectionEngine.self) private var selectionEngine

    /// Scheduled, not-yet-done tasks, soonest first.
    @Query(
        filter: #Predicate<TodayTask> { $0.scheduledAt != nil && $0.doneAt == nil },
        sort: \TodayTask.scheduledAt
    )
    private var tasks: [TodayTask]

    /// Draft title for the add form.
    @State private var newTitle = ""
    /// Draft estimate (minutes); empty means "no estimate".
    @State private var newMinutes = ""
    /// Draft scheduled time. Defaults to one hour ahead so a freshly added
    /// task isn't instantly due/red.
    @State private var newDate = Date.now.addingTimeInterval(3600)

    var body: some View {
        // `.everyMinute` re-evaluates the body each minute, which refreshes the
        // due-state computation below without any user interaction.
        TimelineView(.everyMinute) { timeline in
            AreaColumn(title: "Scheduled", totalTime: tasks.totalEstimateLabel, accent: .orange) {
                VStack(alignment: .leading, spacing: 8) {
                    addForm
                    taskList(now: timeline.date)
                }
            }
        }
    }

    /// Two-row add form: title + add button on top, date-time + minutes below.
    private var addForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Add a scheduled task", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                Button(action: addTask) {
                    Image(systemName: "plus")
                }
                // Disabled until there's a non-empty title to add.
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 6) {
                DatePicker(
                    "Scheduled time",
                    selection: $newDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                // The placeholder text above already explains the field; hide
                // the label to fit the narrow column.
                .labelsHidden()
                TextField("min", text: $newMinutes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 44)
                    .onSubmit(addTask)
            }
        }
    }

    /// The scheduled list (or an empty-state caption). `now` comes from the
    /// timeline so due-state stays current.
    @ViewBuilder
    private func taskList(now: Date) -> some View {
        if tasks.isEmpty {
            // Empty state so the section reads clearly before anything is scheduled.
            Text("Nothing scheduled.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(tasks) { task in
                        // Static row or the inline editor while being edited.
                        Group {
                            if selectionEngine.isEditing(task.id, in: .scheduled) {
                                InlineTaskEditor(task: task, area: .scheduled)
                            } else {
                                ScheduledRow(task: task, now: now) {
                                    TaskManager.moveScheduledToToday(task, in: modelContext)
                                }
                            }
                        }
                        .taskSelectable(task, in: .scheduled)
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
                    guard selectionEngine.focusedArea == .scheduled, let newID else { return }
                    proxy.scrollTo(newID)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// Validates and creates a scheduled task from the draft fields, then
    /// resets them (the date back to "one hour ahead").
    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let minutes = Int(newMinutes.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
        TaskManager.schedule(title: title, estimatedMinutes: minutes, at: newDate, in: modelContext)
        newTitle = ""
        newMinutes = ""
        newDate = Date.now.addingTimeInterval(3600)
    }
}

/// One scheduled row: move-to-Today button, title with the scheduled time
/// below it, and the estimate. The time (and the move button) turn red once
/// the scheduled time has passed, prompting the move to Today.
private struct ScheduledRow: View {
    /// The task to display.
    let task: TodayTask
    /// Current time from the enclosing timeline; drives the due check.
    let now: Date
    /// Invoked by the leading button to move the task to Today.
    let moveToToday: () -> Void

    /// Whether the scheduled time has arrived.
    private var isDue: Bool { task.isDue(asOf: now) }

    var body: some View {
        HStack(spacing: 8) {
            // Move to Today; tinted red as a prompt once the task is due.
            Button(action: moveToToday) {
                Image(systemName: isDue ? "exclamationmark.circle.fill" : "arrow.right.circle")
                    .foregroundStyle(isDue ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Move to Today")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .lineLimit(1)
                // Scheduled time, e.g. "Jun 11, 9:30". Red once due.
                if let scheduledAt = task.scheduledAt {
                    Text(scheduledAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(isDue ? Color.red : Color.secondary)
                }
            }

            Spacer(minLength: 4)

            // Trailing estimate (e.g. "45m"); hidden entirely when unestimated.
            if let estimateLabel = task.estimateLabel {
                Text(estimateLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        // Soften the flip to the red due treatment.
        .animation(.easeInOut(duration: 0.3), value: isDue)
    }
}

// MARK: - Waiting section

/// Bottom section: condition-based waiting tasks (oldest first) with an
/// optional "waiting for…" note. The leading button marks the condition
/// cleared and moves the task to Today.
private struct WaitingSectionView: View {
    /// Shared context for mutations.
    @Environment(\.modelContext) private var modelContext
    /// Selection engine for row selection and inline editing.
    @Environment(SelectionEngine.self) private var selectionEngine

    /// Waiting, not-yet-done tasks, oldest first.
    @Query(
        filter: #Predicate<TodayTask> { $0.startedWaitingAt != nil && $0.doneAt == nil },
        sort: \TodayTask.startedWaitingAt
    )
    private var tasks: [TodayTask]

    /// Draft title for the add form.
    @State private var newTitle = ""
    /// Draft estimate (minutes); empty means "no estimate".
    @State private var newMinutes = ""
    /// Draft waiting-condition note; empty means "no note".
    @State private var newNote = ""

    var body: some View {
        AreaColumn(title: "Waiting", totalTime: tasks.totalEstimateLabel, accent: .purple) {
            VStack(alignment: .leading, spacing: 8) {
                addForm
                taskList
            }
        }
    }

    /// Two-row add form: title + add button on top, condition note + minutes below.
    private var addForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Add a waiting task", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                Button(action: addTask) {
                    Image(systemName: "plus")
                }
                // Disabled until there's a non-empty title to add.
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 6) {
                TextField("Waiting for… (optional)", text: $newNote)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                TextField("min", text: $newMinutes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 44)
                    .onSubmit(addTask)
            }
        }
    }

    /// The waiting list (or an empty-state caption).
    @ViewBuilder
    private var taskList: some View {
        if tasks.isEmpty {
            // Empty state so the section reads clearly before anything waits.
            Text("Not waiting on anything.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(tasks) { task in
                        // Static row or the inline editor while being edited.
                        Group {
                            if selectionEngine.isEditing(task.id, in: .waiting) {
                                InlineTaskEditor(task: task, area: .waiting)
                            } else {
                                WaitingRow(task: task) {
                                    TaskManager.moveWaitingToToday(task, in: modelContext)
                                }
                            }
                        }
                        .taskSelectable(task, in: .waiting)
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
                    guard selectionEngine.focusedArea == .waiting, let newID else { return }
                    proxy.scrollTo(newID)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// Validates and creates a waiting task from the draft fields, then clears
    /// them. An empty note is stored as nil so the row hides the caption.
    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let minutes = Int(newMinutes.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
        let note = newNote.trimmingCharacters(in: .whitespaces)
        TaskManager.startWaiting(
            title: title,
            estimatedMinutes: minutes,
            note: note.isEmpty ? nil : note,
            in: modelContext
        )
        newTitle = ""
        newMinutes = ""
        newNote = ""
    }
}

/// One waiting row: condition-cleared button, title with the waiting note
/// below it, and the estimate.
private struct WaitingRow: View {
    /// The task to display.
    let task: TodayTask
    /// Invoked by the leading button when the condition is cleared.
    let moveToToday: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // The "condition cleared" action: moves the task to Today.
            Button(action: moveToToday) {
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Condition cleared - move to Today")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .lineLimit(1)
                // Why the task is waiting (e.g. "waiting for reply").
                if let note = task.waitingNote, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Trailing estimate (e.g. "45m"); hidden entirely when unestimated.
            if let estimateLabel = task.estimateLabel {
                Text(estimateLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    WaitingAreaView()
        .frame(width: 260, height: 600)
        .modelContainer(for: TodayTask.self, inMemory: true)
}
