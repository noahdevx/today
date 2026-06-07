import SwiftUI

/// Structured Map. A minimap of the Structured area that highlights the task
/// currently hovered in Today. Real rendering and hover-linking arrive in Step 5;
/// for now it draws placeholder bars.
struct MinimapView: View {
    var body: some View {
        VStack(spacing: 8) {
            // Placeholder rows standing in for the minimap's condensed nodes.
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 18)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
