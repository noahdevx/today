import AppKit
import HotKey
import SwiftUI

/// User-selectable presets for the global show/hide shortcut.
///
/// The same shortcut is needed in two different type systems:
/// - HotKey / Carbon (`Key` + `NSEvent.ModifierFlags`): used to actually
///   register the system-wide hotkey that toggles the panel. This is the real
///   trigger.
/// - SwiftUI (`KeyEquivalent` + `EventModifiers`): used only to *display* the
///   shortcut next to the menu bar item. The menu shortcut does not drive the
///   toggle (the HotKey registration does); it exists so users can discover
///   the key combination.
///
/// Both representations are defined per preset, side by side, so the shortcut
/// shown in the menu always matches the hotkey that is actually registered.
///
/// The selection is persisted in UserDefaults under `defaultsKey`: Settings
/// writes it via `@AppStorage`, and `AppDelegate.refreshHotKey()` re-registers
/// the hotkey when it changes. Presets (instead of a free-form key recorder)
/// keep the implementation simple and avoid clashing with system shortcuts.
enum GlobalShortcut: String, CaseIterable, Identifiable {
    /// Option-Command-T (default; "T for Today").
    case optionCommandT
    /// Control-Command-T.
    case controlCommandT
    /// Control-Option-T.
    case controlOptionT
    /// Control-Option-Space.
    case controlOptionSpace

    /// UserDefaults key under which the selected preset's raw value is stored.
    static let defaultsKey = "globalShortcut"

    /// The currently selected preset. Falls back to the default when nothing
    /// (or an unknown value) is stored.
    static var current: GlobalShortcut {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        return GlobalShortcut(rawValue: raw) ?? .optionCommandT
    }

    /// `Identifiable` conformance so the Settings picker can iterate `allCases`.
    var id: String { rawValue }

    /// Human-readable label for the Settings picker, using the standard macOS
    /// modifier symbols.
    var label: String {
        switch self {
        case .optionCommandT: "⌥⌘T"
        case .controlCommandT: "⌃⌘T"
        case .controlOptionT: "⌃⌥T"
        case .controlOptionSpace: "⌃⌥Space"
        }
    }

    /// HotKey (Carbon) key for registration.
    var hotKeyKey: Key {
        switch self {
        case .optionCommandT, .controlCommandT, .controlOptionT: .t
        case .controlOptionSpace: .space
        }
    }

    /// HotKey (Carbon) modifiers for registration.
    var hotKeyModifiers: NSEvent.ModifierFlags {
        switch self {
        case .optionCommandT: [.option, .command]
        case .controlCommandT: [.control, .command]
        case .controlOptionT, .controlOptionSpace: [.control, .option]
        }
    }

    /// SwiftUI key for displaying the shortcut in the menu.
    var menuKey: KeyEquivalent {
        switch self {
        case .optionCommandT, .controlCommandT, .controlOptionT: "t"
        case .controlOptionSpace: .space
        }
    }

    /// SwiftUI modifiers for displaying the shortcut in the menu.
    var menuModifiers: EventModifiers {
        switch self {
        case .optionCommandT: [.option, .command]
        case .controlCommandT: [.control, .command]
        case .controlOptionT, .controlOptionSpace: [.control, .option]
        }
    }
}
