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

        // Apply the persisted appearance before any window is created.
        applyTheme()

        // Route hotkey presses to the toggle.
        hotKeyManager.onToggle = { [weak self] in
            self?.togglePanel()
        }
        hotKeyManager.register()
    }

    // MARK: - Settings support

    /// Re-registers the global hotkey with the preset currently stored in
    /// UserDefaults. Called by Settings when the user picks a different preset.
    func refreshHotKey() {
        hotKeyManager.register()
    }

    /// Applies the persisted theme app-wide. A `nil` appearance clears the
    /// override so windows follow the system appearance again.
    func applyTheme() {
        NSApp.appearance = AppTheme.current.appearance
    }

    // MARK: - Panel control

    /// Shows the panel if hidden, hides it if visible. When the panel is
    /// visible but lost focus (behind other windows after `resignKey` dropped
    /// it from floating level), the hotkey brings it back to the front
    /// instead of hiding it.
    func togglePanel() {
        if let panel, panel.isVisible, panel.isKeyWindow {
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
