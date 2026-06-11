import Foundation

/// Compact, human-readable formatting for work-time durations.
///
/// Kept separate from the `TodayTask` model definition so the persistence model
/// stays focused on stored properties while the display/derived time logic lives
/// here. The formatter is a pure function, which makes it trivial to unit-test.
enum TimeFormatting {
    /// Formats a minute count per the spec: under an hour shows just minutes
    /// ("45m"); an exact hour drops the minutes ("1h"); otherwise both parts are
    /// shown ("1h 30m"). Zero formats as "0m".
    static func durationLabel(minutes: Int) -> String {
        // Clamp to non-negative: estimates are never negative, and this avoids a
        // misleading "-5m" if a bad value ever reaches here.
        let total = max(0, minutes)
        let hours = total / 60
        let remainingMinutes = total % 60
        if hours == 0 {
            return "\(remainingMinutes)m"
        }
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }
}

// MARK: - Per-task and aggregate time labels

extension TodayTask {
    /// Pre-formatted estimate for a single task, or `nil` when unestimated, so the
    /// UI can hide the label instead of showing a misleading "0m".
    var estimateLabel: String? {
        guard let estimatedMinutes else { return nil }
        return TimeFormatting.durationLabel(minutes: estimatedMinutes)
    }
}

extension Collection where Element == TodayTask {
    /// Sum of the collection's estimates in minutes; unestimated tasks count as 0.
    var totalEstimatedMinutes: Int {
        reduce(0) { $0 + ($1.estimatedMinutes ?? 0) }
    }

    /// The collection's total estimate formatted for an area header (e.g. "1h 30m").
    var totalEstimateLabel: String {
        TimeFormatting.durationLabel(minutes: totalEstimatedMinutes)
    }
}

// MARK: - Subtree aggregation (recursive)

extension TodayTask {
    /// Total estimated minutes for this task and its entire subtree. Unestimated
    /// tasks contribute zero. The result includes the task's own estimate plus
    /// every descendant, regardless of nesting depth.
    var subtreeEstimatedMinutes: Int {
        let own = estimatedMinutes ?? 0
        return own + children.reduce(0) { $0 + $1.subtreeEstimatedMinutes }
    }

    /// Formatted subtree total for display in the Structured area (e.g. "2h 30m").
    var subtreeEstimateLabel: String {
        TimeFormatting.durationLabel(minutes: subtreeEstimatedMinutes)
    }
}
