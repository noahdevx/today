import AppKit
import SwiftUI

/// Application entry point.
///
/// Two scenes: a `MenuBarExtra` (the app lives in the menu bar; with
/// `LSUIElement` set it shows no Dock icon and opens no window on launch) and
/// the standard `Settings` window. The actual workspace UI is an `NSPanel`
/// managed by `AppDelegate`.
@main
struct TodayApp: App {
    /// Bridges to an AppKit delegate so we can own an `NSPanel` and a global
    /// hotkey, which SwiftUI scenes alone can't express.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The persistent menu bar item (the "checklist" icon) and its menu.
        MenuBarExtra("Today", systemImage: "checklist") {
            MenuBarCommands()
        }
        // `.menu` = a plain pull-down menu (vs `.window`, a popover). We only
        // need simple commands here, so the menu style is enough.
        .menuBarExtraStyle(.menu)

        // The standard macOS Settings window (shortcut preset + appearance),
        // opened from the menu via SettingsLink.
        Settings {
            SettingsView()
        }
    }
}

/// The menu shown when clicking the menu bar icon.
private struct MenuBarCommands: View {
    /// Persisted shortcut selection. Reading it via @AppStorage keeps the
    /// displayed menu shortcut in sync when the user changes the preset in
    /// Settings.
    @AppStorage(GlobalShortcut.defaultsKey)
    private var shortcutRaw = GlobalShortcut.optionCommandT.rawValue

    /// The selected preset (falls back to the default for unknown values).
    private var shortcut: GlobalShortcut {
        GlobalShortcut(rawValue: shortcutRaw) ?? .optionCommandT
    }

    var body: some View {
        // Toggle the floating panel. The `.keyboardShortcut` here is display-only:
        // it shows the shortcut next to the menu item so users can discover it.
        // The actual global toggle is handled by HotKeyManager. Both read the
        // same GlobalShortcut preset, so the displayed hint always matches the
        // real hotkey.
        Button("Show / Hide Today") {
            AppDelegate.shared?.togglePanel()
        }
        .keyboardShortcut(shortcut.menuKey, modifiers: shortcut.menuModifiers)

        Divider()

        // Opens the Settings scene declared in TodayApp.
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Divider()

        // Because the app has no Dock icon, the menu must offer a way to quit.
        Button("Quit Today") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
