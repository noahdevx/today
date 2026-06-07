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
        // Keep the panel above ordinary windows so it works as a quick overlay.
        level = .floating
        // Show on every Space and over full-screen apps, so the hotkey works
        // regardless of which Space/app is active.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Do NOT auto-hide when the app deactivates; visibility is controlled
        // explicitly via the hotkey/menu instead.
        hidesOnDeactivate = false
        // Keep the instance alive after closing so we can reuse it (paired with
        // ordering it out rather than closing).
        isReleasedWhenClosed = false
        // Let users drag the window by its background, since the title bar is
        // hidden.
        isMovableByWindowBackground = true
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

    /// Allow the borderless-style panel to receive keyboard focus (needed for
    /// future text input and for Escape to reach `cancelOperation`).
    override var canBecomeKey: Bool { true }
    /// Allow the panel to act as the main window when focused.
    override var canBecomeMain: Bool { true }

    /// Hide (not destroy) the panel when the user presses Escape.
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
