import AppKit
import SwiftData
import SwiftUI

/// Owns the floating panel and the global hotkey, and connects the menu bar
/// commands to the panel toggle.
///
/// Lives in AppKit (not pure SwiftUI) because an `NSPanel` and a system-wide
/// hotkey require AppKit APIs.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Weak shared reference so the SwiftUI `MenuBarExtra` menu can reach the
    /// delegate. Weak because the system already retains the delegate for the
    /// app's lifetime; this avoids a retain cycle.
    private(set) static weak var shared: AppDelegate?

    /// The floating workspace panel. Created lazily on first show and reused.
    private var panel: FloatingPanel?
    /// Registers and listens for the global toggle hotkey.
    private let hotKeyManager = HotKeyManager()

    /// Runs once at launch. Note: it deliberately does NOT show the panel, which
    /// is why only the menu bar icon appears at startup.
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Touch the shared container early so the on-disk store is initialized
        // at launch rather than on first panel open.
        _ = AppState.shared.modelContainer

        // Route hotkey presses to the toggle.
        hotKeyManager.onToggle = { [weak self] in
            self?.togglePanel()
        }
        hotKeyManager.register()
    }

    // MARK: - Panel control

    /// Shows the panel if hidden, hides it if visible. Single entry point used by
    /// both the hotkey and the menu.
    func togglePanel() {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    /// Brings the panel to the front, creating it on first use.
    func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel

        // Activate first so the (agent) app can take focus, then front the panel.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hides the panel without destroying it (so its state/content is preserved).
    func hidePanel() {
        panel?.orderOut(nil)
    }

    /// Builds the panel and injects the shared SwiftData container into its
    /// SwiftUI content. Called only the first time the panel is shown.
    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel {
            ContentView()
                .modelContainer(AppState.shared.modelContainer)
        }
        panel.center()
        return panel
    }
}
