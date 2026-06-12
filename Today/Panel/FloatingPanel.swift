import AppKit
import SwiftUI

/// A Spotlight-style floating panel that hosts SwiftUI content. It floats above
/// other apps, appears on every Space, and can become key to accept input.
final class FloatingPanel: NSPanel {
    /// Creates the panel with the given SwiftUI content embedded via an
    /// `NSHostingView`.
    init<Content: View>(@ViewBuilder content: () -> Content) {
        // Window chrome:
        // - .titled / .closable / .resizable: a normal resizable window frame.
        // - .fullSizeContentView: let content extend under the (transparent)
        //   title bar for an edge-to-edge look.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // --- Floating behavior settings (what each does and why) ---

        // Marks this as a utility/floating panel (panels behave differently from
        // normal windows, e.g. they don't become the app's main window).
        isFloatingPanel = true
        // Keep the panel above ordinary windows whenever it is visible.
        // Spotlight-style dismissal (AppDelegate hides the panel when the app
        // deactivates) guarantees "visible" implies "in use", so the level
        // never needs to change.
        level = .floating
        // Show on every Space and over full-screen apps, so the hotkey works
        // regardless of which Space/app is active.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Hiding on deactivation is handled by AppDelegate (hidePanel in
        // applicationDidResignActive) instead of this flag: the built-in
        // behavior would also re-show the panel automatically whenever the
        // app activates again (e.g. just to use Settings), which we don't
        // want - the hotkey/menu is the only way to bring the panel back.
        hidesOnDeactivate = false
        // Keep the instance alive after closing so we can reuse it (paired with
        // ordering it out rather than closing).
        isReleasedWhenClosed = false
        // Window dragging is handled by the dedicated WindowDragHandle at the
        // top of ContentView. Disabled here so SwiftUI .draggable modifiers
        // (e.g. structured task drag-to-Today) work without accidentally
        // triggering a window move.
        isMovableByWindowBackground = false
        // Use the lightweight utility-window show/hide animation.
        animationBehavior = .utilityWindow

        // --- Hide the title bar chrome for a clean, panel-like appearance ---
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // Embed the SwiftUI content and make it resize with the panel.
        let hostingView = NSHostingView(rootView: content())
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    /// Required by `NSCoding`, but this panel is only created in code, never from
    /// a nib/storyboard, so it is intentionally unavailable.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for FloatingPanel")
    }

    /// Allow the panel to receive keyboard focus (so Escape reaches
    /// `cancelOperation`, and for future text input).
    ///
    /// Currently redundant: a `.titled` window can already become key. Kept as
    /// insurance for a future borderless / non-activating Spotlight-style
    /// redesign, where this override becomes required.
    override var canBecomeKey: Bool { true }

    /// Hide (not destroy) the panel when the user presses Escape.
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    /// Routes Cmd-Z / Shift-Cmd-Z to the SwiftData undo manager.
    ///
    /// As a menu bar (LSUIElement) app there is no Edit menu to provide the
    /// standard undo/redo key equivalents, so the panel resolves them itself.
    /// While a text field is being edited (the first responder is the field
    /// editor) the keys are left to the text system, which manages its own
    /// undo stack for typing.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only plain Cmd-Z / Shift-Cmd-Z are handled here.
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isUndo = modifiers == .command && event.charactersIgnoringModifiers == "z"
        let isRedo = modifiers == [.command, .shift] && event.charactersIgnoringModifiers == "z"
        guard isUndo || isRedo else {
            return super.performKeyEquivalent(with: event)
        }

        // Text editing in progress: defer to the field editor's own undo.
        if firstResponder is NSTextView {
            return super.performKeyEquivalent(with: event)
        }

        // Apply to the shared store's undo stack (changes are registered
        // automatically by SwiftData).
        guard let undoManager = AppState.shared.modelContainer.mainContext.undoManager else {
            return super.performKeyEquivalent(with: event)
        }
        if isUndo, undoManager.canUndo {
            undoManager.undo()
            return true
        }
        if isRedo, undoManager.canRedo {
            undoManager.redo()
            return true
        }
        return true
    }
}
