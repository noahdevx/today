import SwiftData
import SwiftUI

// MARK: - Row selection

/// Gives a row the standard selection behaviors: click to select, and an
/// accent ring while it is the current selection. Applied to every task row
/// (Today, Done, Structured, Scheduled, Waiting) so the keyboard cursor looks
/// and behaves the same everywhere.
struct TaskSelectionModifier: ViewModifier {
    /// The task this row shows.
    let task: TodayTask
    /// The area the row lives in (the same task can appear in two columns;
    /// only the focused area's row shows the ring).
    let area: AreaKind

    @Environment(SelectionEngine.self) private var selectionEngine

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            // Click selects (and re-focuses the row's area). A simultaneous
            // gesture (instead of .onTapGesture) keeps the recognizer from
            // competing with drag interactions: an exclusive tap recognizer
            // delays/steals the mouse-down that List reordering and .onDrag
            // need, which made rows hard to grab.
            .simultaneousGesture(
                TapGesture().onEnded {
                    selectionEngine.select(task, in: area)
                }
            )
            // Accent ring marks the selected row.
            .overlay {
                if selectionEngine.isSelected(task.id, in: area) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                }
            }
    }
}

extension View {
    /// Sugar for applying `TaskSelectionModifier`.
    func taskSelectable(_ task: TodayTask, in area: AreaKind) -> some View {
        modifier(TaskSelectionModifier(task: task, area: area))
    }
}

// MARK: - Inline editor

/// Inline editor swapped into a row while its task is being edited: a title
/// field plus a minutes field, backed by drafts that commit through
/// TaskManager.
///
/// Standard editing keyboard flow:
/// - Space (handled by ContentView) opens the editor on the title field.
/// - Enter in either field commits and ends editing.
/// - Tab in the title field commits and moves focus to the minutes field.
/// - Tab in the minutes field commits and advances to the next task's title.
/// - Escape (handled by ContentView) closes the editor without committing.
struct InlineTaskEditor: View {
    /// The task being edited.
    let task: TodayTask
    /// The area whose row hosts this editor.
    let area: AreaKind

    @Environment(\.modelContext) private var modelContext
    @Environment(SelectionEngine.self) private var selectionEngine

    /// Draft values, seeded from the task when the editor appears so typing
    /// never mutates the model until a commit.
    @State private var draftTitle = ""
    @State private var draftMinutes = ""
    /// Which of the two fields owns keyboard focus, mirrored from the engine.
    @FocusState private var focusedField: SelectionEngine.EditingField?

    var body: some View {
        HStack(spacing: 6) {
            TextField("Title", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .title)
                .onSubmit(commitAndEnd)
                // Tab: commit and hop to the minutes field (instead of the
                // default focus traversal).
                .onKeyPress(.tab) {
                    commit()
                    selectionEngine.editingField = .minutes
                    return .handled
                }

            TextField("min", text: $draftMinutes)
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
                .focused($focusedField, equals: .minutes)
                .onSubmit(commitAndEnd)
                // Tab: commit and advance to the next task's title editor.
                .onKeyPress(.tab) {
                    commit()
                    selectionEngine.editNextTask(context: modelContext)
                    return .handled
                }
        }
        // Seed drafts and take focus when the editor appears.
        .onAppear {
            draftTitle = task.title
            draftMinutes = task.estimatedMinutes.map(String.init) ?? ""
            focusedField = selectionEngine.editingField
        }
        // Follow engine-driven focus hops (title -> minutes).
        .onChange(of: selectionEngine.editingField) { _, newField in
            focusedField = newField
        }
    }

    /// Writes both drafts through TaskManager. An empty/invalid minutes draft
    /// clears the estimate; rename ignores empty titles.
    private func commit() {
        TaskManager.rename(task, to: draftTitle, in: modelContext)
        let minutes = Int(draftMinutes.trimmingCharacters(in: .whitespaces))
        TaskManager.setEstimate(task, minutes: minutes, in: modelContext)
    }

    /// Commit then leave editing mode (Enter).
    private func commitAndEnd() {
        commit()
        selectionEngine.editingField = nil
    }
}
