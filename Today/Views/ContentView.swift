import AppKit
import SwiftData
import SwiftUI

/// The main floating-panel layout.
///
/// A drag handle on top, then the five columns: Today | (Done) | Structured |
/// Map | Waiting. All areas are data-driven; the Done column is toggled from
/// the Today header (or Cmd-D).
struct ContentView: View {
    /// Context for keyboard-driven mutations (delete) and navigation fetches.
    @Environment(\.modelContext) private var modelContext

    /// Shared hover state for the Today → Structured/Map highlight link.
    @State private var hoverEngine = HoverLinkEngine()
    /// App-wide selection, keyboard-navigation, editing, and tree state.
    /// Owns the Done-column visibility so navigation/search can open it.
    @State private var selectionEngine = SelectionEngine()
    /// Keyboard focus of the panel content itself. Programmatically restored
    /// after a task gets selected (row click, search jump) so the arrow keys
    /// work immediately instead of staying trapped in the last text field.
    @FocusState private var isPanelFocused: Bool

    /// Active Today tasks in display order; the head of this list is the "Now"
    /// task, published app-wide via the `nowTaskID` environment key.
    @Query(
        filter: #Predicate<TodayTask> { $0.todayOrder != nil && $0.doneAt == nil },
        sort: \TodayTask.todayOrder
    )
    private var todayTasks: [TodayTask]

    var body: some View {
        // Bindable wrapper so SwiftUI bindings (e.g. the Done toggle) can
        // write into the @Observable engine.
        @Bindable var selectionEngine = selectionEngine

        VStack(spacing: 0) {
            // Top bar: window drag handle plus the search field. zIndex lifts
            // the bar (and the search dropdown overlay) above the columns.
            topBar
                .zIndex(1)

            Divider()

            // Horizontal row of columns: Today | (Done) | Structured | Map | Waiting.
            HStack(spacing: 0) {
                TodayAreaView(showDone: $selectionEngine.isDoneVisible)
                    .frame(width: 260)

                Divider()

                if selectionEngine.isDoneVisible {
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
        .animation(.easeInOut(duration: 0.2), value: selectionEngine.isDoneVisible)
        .frame(minWidth: 920, minHeight: 520)
        .background(.regularMaterial)
        .environment(hoverEngine)
        .environment(selectionEngine)
        // Publish the Now task (head of Today) so any area can highlight it.
        .environment(\.nowTaskID, todayTasks.first?.id)
        // --- Keyboard navigation (active while no text field has focus) ---
        // Make the panel content itself focusable so the commands below fire
        // even before any control is clicked; hide the focus ring.
        .focusable()
        .focusEffectDisabled()
        .focused($isPanelFocused)
        // Arrow keys: up/down move within the area; in the structured tree,
        // right expands (or steps into) and left collapses (or steps out of)
        // the selected node, standard outline-view style. Keyboard moves are
        // focus interactions, so they hand the live link highlight back to
        // the focus side (clearing any hover).
        .onMoveCommand { direction in
            hoverEngine.hoveredTaskID = nil
            switch direction {
            case .up: selectionEngine.moveSelection(.up, context: modelContext)
            case .down: selectionEngine.moveSelection(.down, context: modelContext)
            case .left: selectionEngine.collapseSelection(context: modelContext)
            case .right: selectionEngine.expandSelection(context: modelContext)
            @unknown default: break
            }
        }
        // Delete / Forward-Delete: remove the selected task.
        .onDeleteCommand {
            hoverEngine.hoveredTaskID = nil
            selectionEngine.deleteSelection(context: modelContext)
        }
        // Space: start editing the selected task's title.
        .onKeyPress(.space) {
            guard selectionEngine.selectedTaskID != nil,
                  selectionEngine.editingField == nil else { return .ignored }
            hoverEngine.hoveredTaskID = nil
            selectionEngine.beginEditingTitle()
            return .handled
        }
        // Tab / Shift-Tab on a structured selection (outside editing):
        // outliner-style indent under the previous sibling / outdent next to
        // the parent. Shift-Tab arrives as a "backtab" character, so both
        // spellings are checked.
        .onKeyPress(phases: .down) { press in
            let isBacktab = press.characters == "\u{19}"
            guard press.key == .tab || isBacktab else { return .ignored }
            guard selectionEngine.editingField == nil,
                  selectionEngine.focusedArea == .structured,
                  selectionEngine.selectedTaskID != nil else { return .ignored }
            hoverEngine.hoveredTaskID = nil
            if isBacktab || press.modifiers.contains(.shift) {
                selectionEngine.outdentSelection(context: modelContext)
            } else {
                selectionEngine.indentSelection(context: modelContext)
            }
            return .handled
        }
        // Escape: cancel editing, then clear selection, then hide the panel
        // (standard staged dismissal).
        .onExitCommand {
            if !selectionEngine.handleEscape() {
                AppDelegate.shared?.hidePanel()
            }
        }
        // Whenever a task gets selected outside editing (row click, search
        // jump, programmatic select), pull keyboard focus back onto the
        // panel so the arrow keys respond immediately.
        .onChange(of: selectionEngine.selectedTaskID) { _, newID in
            if newID != nil, selectionEngine.editingField == nil {
                isPanelFocused = true
            }
        }
        // Start with the keyboard cursor on the Now task so the panel opens
        // ready to work on what matters first.
        .onAppear {
            if selectionEngine.selectedTaskID == nil, let nowTask = todayTasks.first {
                selectionEngine.select(nowTask, in: .today)
            }
            isPanelFocused = true
        }
    }

    /// Thin bar at the top of the panel: a draggable region (the only region
    /// that moves the panel window, so SwiftUI drag sources keep working in
    /// the content below) with a capsule affordance, and the search field on
    /// the trailing edge.
    private var topBar: some View {
        HStack(spacing: 8) {
            WindowDragHandle()
                .frame(maxWidth: .infinity)
                .overlay {
                    Capsule()
                        .fill(.quaternary)
                        .frame(width: 36, height: 4)
                }

            SearchBarView()
                .padding(.trailing, 8)
        }
        .frame(height: 28)
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
