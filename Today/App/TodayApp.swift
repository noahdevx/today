import AppKit
import SwiftUI

/// Application entry point.
///
/// The only scene is a `MenuBarExtra`, so the app lives in the menu bar and (with
/// `LSUIElement` set in the build settings) shows no Dock icon and opens no
/// window on launch. The actual workspace UI is an `NSPanel` managed by
/// `AppDelegate`.
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
    }
}

/// The menu shown when clicking the menu bar icon.
private struct MenuBarCommands: View {
    var body: some View {
        // Toggle the floating panel. The `.keyboardShortcut` here is display-only:
        // it shows the shortcut next to the menu item so users can discover it.
        // The actual global toggle is handled by HotKeyManager. Both read
        // GlobalShortcut, so the displayed hint always matches the real hotkey.
        Button("Show / Hide Today") {
            AppDelegate.shared?.togglePanel()
        }
        .keyboardShortcut(GlobalShortcut.menuKey, modifiers: GlobalShortcut.menuModifiers)

        Divider()

        // Because the app has no Dock icon, the menu must offer a way to quit.
        Button("Quit Today") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
