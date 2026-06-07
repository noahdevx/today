import SwiftUI

/// Today area (left-most column). Cross-project, single-column ordering of what
/// to tackle today. PR 1 shows the header (total time + Done toggle) and a
/// placeholder list; the real task list arrives in Step 3.
struct TodayAreaView: View {
    /// Bound to the parent so the header's Done button can show/hide the Done
    /// column.
    @Binding var showDone: Bool

    var body: some View {
        AreaColumn(title: "Today", totalTime: "0m", accent: .yellow) {
            VStack(alignment: .leading, spacing: 10) {
                // Toggles the Done column. Icon flips to indicate open/closed.
                Button {
                    showDone.toggle()
                } label: {
                    Label("Done", systemImage: showDone ? "chevron.left" : "checkmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Stand-in for the future ordered task list.
                AreaPlaceholder(note: "Tasks for today (Step 3)")
            }
        }
    }
}
