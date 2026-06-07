import SwiftUI

/// Structured area. Project / folder hierarchy with unlimited nesting and
/// per-node time totals. The tree, collapsing, and drag-to-Today are implemented
/// in Step 4.
struct StructuredAreaView: View {
    var body: some View {
        AreaColumn(title: "Structured", accent: .blue) {
            AreaPlaceholder(note: "Project hierarchy (Step 4)")
        }
    }
}
