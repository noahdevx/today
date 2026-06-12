import Foundation
import SwiftUI

/// Environment keys for the cross-area task links (Now badge and the
/// hover/selection highlight chain).

/// Environment key carrying the ID of the "Now" task.
///
/// The Now task is the task at the head of the Today column - the one the user
/// is (or should be) working on right now. ContentView owns the Today query
/// and publishes the first task's ID through this key so any area view
/// (Today's NOW section, Structured's NOW badge) can mark it without
/// duplicating the query in every consumer.
private struct NowTaskIDKey: EnvironmentKey {
    /// No Now task by default (Today column empty or environment not set).
    static let defaultValue: UUID? = nil
}

/// Environment key carrying the ancestor IDs of the task that is currently
/// hovered or selected anywhere in the app.
///
/// StructuredAreaView computes the chain (it already queries every task) and
/// injects it into the tree; a collapsed node contained in this set knows a
/// highlighted task is hidden inside its subtree and stands in for it
/// visually.
private struct LinkedAncestorIDsKey: EnvironmentKey {
    /// Empty by default: nothing hovered/selected, nothing to stand in for.
    static let defaultValue: Set<UUID> = []
}

extension EnvironmentValues {
    /// The persistent ID of the Now task (head of the Today column), or `nil`
    /// when the Today column is empty.
    var nowTaskID: UUID? {
        get { self[NowTaskIDKey.self] }
        set { self[NowTaskIDKey.self] = newValue }
    }

    /// Ancestor IDs of the task currently hovered or selected anywhere in
    /// the app (empty when none).
    var linkedAncestorIDs: Set<UUID> {
        get { self[LinkedAncestorIDsKey.self] }
        set { self[LinkedAncestorIDsKey.self] = newValue }
    }
}
