import AppKit
import HotKey
import SwiftUI

/// Single source of truth for the global show/hide shortcut (Option-Command-T).
///
/// The same shortcut is needed in two different type systems:
/// - HotKey / Carbon (`Key` + `NSEvent.ModifierFlags`): used to actually
///   register the system-wide hotkey that toggles the panel. This is the real
///   trigger.
/// - SwiftUI (`KeyEquivalent` + `EventModifiers`): used only to *display* the
///   shortcut next to the menu item. The menu shortcut does not drive the toggle
///   (the HotKey registration does); it exists so users can discover the key
///   combination.
///
/// Both representations are defined here, side by side, so the shortcut shown in
/// the menu always matches the hotkey that is actually registered. If you change
/// the shortcut, update both pairs below.
enum GlobalShortcut {
    /// HotKey (Carbon) key for registration.
    ///
    /// `nonisolated(unsafe)`: HotKey's `Key` is not marked `Sendable` (the library
    /// predates Swift 6 strict concurrency), but this is an immutable `let`, so
    /// sharing it across actors is safe.
    nonisolated(unsafe) static let hotKeyKey: Key = .t
    /// HotKey (Carbon) modifiers for registration.
    static let hotKeyModifiers: NSEvent.ModifierFlags = [.command, .option]

    /// SwiftUI key for displaying the shortcut in the menu.
    static let menuKey: KeyEquivalent = "t"
    /// SwiftUI modifiers for displaying the shortcut in the menu.
    static let menuModifiers: EventModifiers = [.command, .option]
}
