import Foundation

/// Tracks which task is currently hovered in *any* area so every other area
/// (and the minimap) can highlight the same task in real time.
///
/// Created once by `ContentView` and injected via `@Environment`. Every task
/// row reports mouse-over through the shared `taskSelectable` modifier; rows
/// and minimap bars whose task matches draw the accent link highlight.
@MainActor
@Observable
final class HoverLinkEngine {
    /// The persistent ID of the task under the pointer, or `nil` when none.
    var hoveredTaskID: UUID?
}
