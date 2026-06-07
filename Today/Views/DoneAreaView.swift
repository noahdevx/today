import SwiftUI

/// Done area (toggled column between Today and Structured). Shows tasks completed
/// today. Full behavior (drag in/out, time totals) is implemented in Step 3.
struct DoneAreaView: View {
    var body: some View {
        // Grey accent signals "completed/de-emphasized" per the design.
        AreaColumn(title: "Done", totalTime: "0m", accent: .gray) {
            AreaPlaceholder(note: "Completed today (Step 3)")
        }
    }
}
