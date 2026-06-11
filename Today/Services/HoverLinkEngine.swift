import Foundation

/// Tracks which task is currently hovered in the Today area so the Structured
/// tree and Minimap can highlight the corresponding node in real time.
///
/// Created once by `ContentView` and injected via `@Environment`. TodayAreaView
/// writes `hoveredTaskID` on mouse-over; StructuredAreaView and MinimapView read
/// it to apply visual highlights. The one-way flow (Today → Structured/Map)
/// matches the design spec.
@MainActor
@Observable
final class HoverLinkEngine {
    /// The persistent ID of the task being hovered in Today, or `nil` when no
    /// task is under the pointer.
    var hoveredTaskID: UUID?
}
