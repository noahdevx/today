import SwiftUI

/// A single task row shared by the Today and Done areas: a leading action button
/// (the status circle), the title, and an optional estimate label on the trailing
/// edge.
///
/// The leading symbol and its action are injected so the same row works in both
/// areas: an empty circle that completes the task in Today, and a filled checkmark
/// that restores it from Done.
struct TaskRow: View {
    /// The task to display.
    let task: TodayTask
    /// SF Symbol for the leading status button (defaults to the Today "to-do"
    /// circle; Done passes a filled checkmark).
    var systemImage: String = "circle"
    /// Invoked when the leading status button is tapped (complete or restore).
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Leading status button: completes (Today) or restores (Done) the task.
            Button(action: action) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            // Task title; truncated so long titles don't break the column width.
            Text(task.title)
                .lineLimit(1)

            Spacer(minLength: 4)

            // Trailing estimate (e.g. "45m"); hidden entirely when unestimated.
            if let estimateLabel = task.estimateLabel {
                Text(estimateLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        // Make the whole row width hit-testable for swipe actions.
        .contentShape(Rectangle())
    }
}
