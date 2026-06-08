import SwiftData
import SwiftUI

/// The main floating-panel layout.
///
/// PR 1 renders the five-area skeleton so the panel and hotkey can be verified.
/// The Today / Done / Structured / Map / Waiting areas are filled in by later
/// steps.
struct ContentView: View {
    /// Whether the Done column is shown. Local UI state for PR 1; the real
    /// toggle/logic arrives in Step 3.
    @State private var showDone = false

    var body: some View {
        // Horizontal row of columns: Today | (Done) | Structured | Map | Waiting.
        HStack(spacing: 0) {
            // Left: the Today column. It owns the Done toggle via a binding.
            TodayAreaView(showDone: $showDone)
                .frame(width: 260)

            Divider()

            // Done column appears between Today and Structured only when toggled.
            if showDone {
                DoneAreaView()
                    .frame(width: 220)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }

            // Structured tree takes the remaining flexible width.
            StructuredAreaView()
                .frame(minWidth: 280, maxWidth: .infinity)

            Divider()

            // Narrow minimap column.
            MinimapView()
                .frame(width: 96)

            Divider()

            // Right: Waiting (Scheduled + Waiting sections).
            WaitingAreaView()
                .frame(width: 260)
        }
        // Animate the Done column appearing/disappearing.
        .animation(.easeInOut(duration: 0.2), value: showDone)
        // Minimum size keeps all five columns usable.
        .frame(minWidth: 920, minHeight: 520)
        // Translucent background for the Spotlight-like panel feel.
        .background(.regularMaterial)
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

/// Placeholder content used inside each area until its step is implemented:
/// two skeleton rows plus a note describing what will go here.
struct AreaPlaceholder: View {
    /// Short description of the eventual content (and which step adds it).
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Two grey skeleton rows hinting at a future list.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(height: 36)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(height: 36)
            // Caption explaining what's coming.
            Text(note)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }
}

#Preview {
    // In-memory store so the @Query-backed Today/Done areas render in previews.
    ContentView()
        .frame(width: 1100, height: 640)
        .modelContainer(for: TodayTask.self, inMemory: true)
}
