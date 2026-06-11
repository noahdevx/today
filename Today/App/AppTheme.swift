import AppKit

/// User-selectable appearance for the app's windows (panel and settings).
///
/// `system` follows the macOS appearance; `light` / `dark` force one. The
/// selection is persisted in UserDefaults under `defaultsKey`: Settings writes
/// it via `@AppStorage`, and `AppDelegate.applyTheme()` applies it app-wide
/// through `NSApp.appearance`.
enum AppTheme: String, CaseIterable, Identifiable {
    /// Follow the system appearance (no override).
    case system
    /// Force light mode.
    case light
    /// Force dark mode.
    case dark

    /// UserDefaults key under which the selected theme's raw value is stored.
    static let defaultsKey = "appTheme"

    /// The currently selected theme. Falls back to `system` when nothing (or
    /// an unknown value) is stored.
    static var current: AppTheme {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        return AppTheme(rawValue: raw) ?? .system
    }

    /// `Identifiable` conformance so the Settings picker can iterate `allCases`.
    var id: String { rawValue }

    /// Human-readable label for the Settings picker.
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The AppKit appearance to apply app-wide. `nil` clears the override so
    /// windows follow the system appearance again.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
