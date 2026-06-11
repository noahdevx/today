import Foundation
import SwiftUI

/// Environment key carrying the ID of the "Now" task.
///
/// The Now task is the task at the head of the Today column - the one the user
/// is (or should be) working on right now. ContentView owns the Today query
/// and publishes the first task's ID through this key so any area view
/// (Today's NOW section, Structured's yellow row) can highlight it without
/// duplicating the query in every consumer.
private struct NowTaskIDKey: EnvironmentKey {
    /// No Now task by default (Today column empty or environment not set).
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    /// The persistent ID of the Now task (head of the Today column), or `nil`
    /// when the Today column is empty.
    var nowTaskID: UUID? {
        get { self[NowTaskIDKey.self] }
        set { self[NowTaskIDKey.self] = newValue }
    }
}
