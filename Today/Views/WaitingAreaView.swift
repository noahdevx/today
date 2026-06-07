import SwiftUI

/// Waiting area (right-most column). Two stacked sections: Scheduled (time-
/// triggered) on top and Waiting (condition-based) below. Behavior is implemented
/// in Step 6.
struct WaitingAreaView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top section: tasks that surface when their scheduled time arrives.
            AreaColumn(title: "Scheduled", totalTime: "0m", accent: .orange) {
                AreaPlaceholder(note: "Time-triggered (Step 6)")
            }

            Divider()

            // Bottom section: tasks blocked on a manual/external condition.
            AreaColumn(title: "Waiting", totalTime: "0m", accent: .purple) {
                AreaPlaceholder(note: "Condition-based (Step 6)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
