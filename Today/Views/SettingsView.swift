import AppKit
import SwiftUI

/// Content of the standard Settings window (opened from the menu bar item).
///
/// Two preferences, both persisted via `@AppStorage` and applied immediately:
/// - Global shortcut: one of the `GlobalShortcut` presets; changing it
///   re-registers the system-wide hotkey.
/// - Appearance: follow the system or force light/dark via `AppTheme`.
struct SettingsView: View {
    /// Raw value of the selected shortcut preset (see `GlobalShortcut`).
    @AppStorage(GlobalShortcut.defaultsKey)
    private var shortcutRaw = GlobalShortcut.optionCommandT.rawValue
    /// Raw value of the selected appearance (see `AppTheme`).
    @AppStorage(AppTheme.defaultsKey)
    private var themeRaw = AppTheme.system.rawValue

    var body: some View {
        Form {
            // Global shortcut: preset picker. A free-form key recorder is
            // intentionally out of scope; presets avoid system-shortcut clashes.
            Picker("Global shortcut", selection: $shortcutRaw) {
                ForEach(GlobalShortcut.allCases) { shortcut in
                    Text(shortcut.label).tag(shortcut.rawValue)
                }
            }

            // Appearance: system / light / dark.
            Picker("Appearance", selection: $themeRaw) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.label).tag(theme.rawValue)
                }
            }
        }
        .formStyle(.grouped)
        // Fixed width keeps the settings window compact; height hugs the form.
        .frame(width: 360)
        .fixedSize()
        // Apply changes immediately so no restart is needed.
        .onChange(of: shortcutRaw) { AppDelegate.shared?.refreshHotKey() }
        .onChange(of: themeRaw) { AppDelegate.shared?.applyTheme() }
        // As a menu bar (LSUIElement) app we must request activation explicitly,
        // or the settings window can open behind the frontmost app's windows.
        // activate() (macOS 14+) replaces the deprecated
        // activate(ignoringOtherApps:); opening Settings is a direct user
        // action, so the system honors the request.
        .onAppear { NSApp.activate() }
    }
}

#Preview {
    SettingsView()
}
