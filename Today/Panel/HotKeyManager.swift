import AppKit
import HotKey

/// Registers a single global hotkey that toggles the floating panel.
///
/// Uses the HotKey library (Carbon `RegisterEventHotKey` under the hood), which
/// works inside the App Sandbox and needs no Accessibility / Input Monitoring
/// permission. The shortcut is one of the `GlobalShortcut` presets, selectable
/// in Settings (default: Option-Command-T).
@MainActor
final class HotKeyManager {
    /// Retained registration. Keeping a reference is what keeps the hotkey alive;
    /// releasing it unregisters the shortcut.
    private var hotKey: HotKey?

    /// Called on the main actor whenever the hotkey is pressed. The owner sets
    /// this to perform the toggle.
    var onToggle: (() -> Void)?

    /// Registers the global shortcut. This is the real, system-wide trigger.
    ///
    /// Calling it again replaces the previous registration (assigning the new
    /// `HotKey` releases the old one, which unregisters it), so this same
    /// method also serves re-registration when the user picks a different
    /// preset in Settings.
    ///
    /// - Parameter shortcut: the preset to register. Defaults to the selection
    ///   persisted in UserDefaults (`GlobalShortcut.current`).
    func register(_ shortcut: GlobalShortcut = .current) {
        let hotKey = HotKey(key: shortcut.hotKeyKey, modifiers: shortcut.hotKeyModifiers)
        // Fire the toggle on key-down.
        hotKey.keyDownHandler = { [weak self] in
            // HotKey dispatches its handler on the main thread, so it is safe to
            // assume main-actor isolation here.
            MainActor.assumeIsolated {
                self?.onToggle?()
            }
        }
        self.hotKey = hotKey
    }
}
