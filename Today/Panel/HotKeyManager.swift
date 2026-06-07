import AppKit
import HotKey

/// Registers a single global hotkey that toggles the floating panel.
///
/// Uses the HotKey library (Carbon `RegisterEventHotKey` under the hood), which
/// works inside the App Sandbox and needs no Accessibility / Input Monitoring
/// permission. The default shortcut is Option-Command-T; it will become
/// user-configurable in a later step.
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
    /// - Parameters:
    ///   - key: the base key. Defaults to `GlobalShortcut.hotKeyKey` (the "Today"
    ///     mnemonic, Option-Command-T).
    ///   - modifiers: required modifiers. Defaults to `GlobalShortcut.hotKeyModifiers`,
    ///     chosen to avoid clashing with common system/app shortcuts.
    func register(
        key: Key = GlobalShortcut.hotKeyKey,
        modifiers: NSEvent.ModifierFlags = GlobalShortcut.hotKeyModifiers
    ) {
        let hotKey = HotKey(key: key, modifiers: modifiers)
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
