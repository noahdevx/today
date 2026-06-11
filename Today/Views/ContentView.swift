import AppKit
import SwiftData
import SwiftUI

/// The main floating-panel layout.
///
/// A drag handle on top, then the five columns: Today | (Done) | Structured |
/// Map | Waiting. All areas are data-driven; the Done column is toggled from
/// the Today header (or Cmd-D).
struct ContentView: View {
    /// Whether the Done column is shown.
    @State private var showDone = false
    /// Shared hover state for the Today → Structured/Map highlight link.
    @State private var hoverEngine = HoverLinkEngine()

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle: the only region that moves the panel window. Keeps
            // SwiftUI .draggable modifiers (structured task drag) working in
            // the content area below.
            dragHandle

            Divider()

            // Horizontal row of columns: Today | (Done) | Structured | Map | Waiting.
            HStack(spacing: 0) {
                TodayAreaView(showDone: $showDone)
                    .frame(width: 260)

                Divider()

                if showDone {
                    DoneAreaView()
                        .frame(width: 220)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }

                StructuredAreaView()
                    .frame(minWidth: 280, maxWidth: .infinity)

                Divider()

                MinimapView()
                    .frame(width: 96)

                Divider()

                WaitingAreaView()
                    .frame(width: 260)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showDone)
        .frame(minWidth: 920, minHeight: 520)
        .background(.regularMaterial)
        .environment(hoverEngine)
    }

    /// Thin bar at the top of the panel that the user can drag to reposition
    /// the window. A small capsule provides a visual affordance.
    private var dragHandle: some View {
        WindowDragHandle()
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .overlay {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 36, height: 4)
            }
    }
}

/// Shared column scaffold used by each area placeholder: a header (accent dot +
/// title + optional total time) above the column's content.
struct AreaColumn<Content: View>: View {
    /// Column title shown in the header.
    let title: String
    /// Optional pre-formatted total-time string (e.g. "1h 30m"); hidden when nil.
    var totalTime: String?
    /// Accent color for the header dot (per-area visual key).
    var accent: Color
    /// The column body.
    @ViewBuilder var content: Content

    /// `totalTime` and `accent` default here (rather than on the stored
    /// properties) so callers can omit them while keeping the declarations clean.
    init(
        title: String,
        totalTime: String? = nil,
        accent: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.totalTime = totalTime
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: colored dot, title, and (optional) total time.
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.headline)
                Spacer()
                if let totalTime {
                    Text(totalTime)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            content

            // Push content to the top of the column.
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Window drag handle

/// Bridges to AppKit so the user can reposition the panel by dragging this
/// region. Replaces the hidden title bar's standard drag behavior; the rest
/// of the content area does not move the window, which lets SwiftUI
/// `.draggable` modifiers (e.g. structured task drag-to-Today) work normally.
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// NSView that forwards mouse-down events to the window's drag machinery.
    class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1100, height: 640)
        .modelContainer(for: TodayTask.self, inMemory: true)
}
