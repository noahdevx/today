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

    // MARK: - Float-on-top lifecycle

    /// Float the panel above other windows while this app is active.
    ///
    /// Raising happens both here and in `FloatingPanel.becomeKey()` (the key
    /// path covers LSUIElement cases where the window is keyed without the
    /// app activating); lowering happens only below on deactivation, so
    /// switching key windows inside the app (e.g. opening Settings) never
    /// drops the panel behind other windows.
    func applicationDidBecomeActive(_ notification: Notification) {
        // isVisible guard: orderFrontRegardless would otherwise re-show a
        // panel the user has hidden.
        guard let panel, panel.isVisible else { return }
        panel.level = .floating
        // Sync the z-order with the restored level immediately.
        panel.orderFrontRegardless()
    }

    /// Drop the panel to the normal window level when the user switches to
    /// another app, so it stops floating over their work.
    func applicationDidResignActive(_ notification: Notification) {
        panel?.level = .normal
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

        // Request activation first so the (agent) app can take focus, then
        // front the panel. activate() (macOS 14+) replaces the deprecated
        // activate(ignoringOtherApps:); the hotkey/menu click is a direct user
        // action, so the system honors the request.
        NSApp.activate()
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
