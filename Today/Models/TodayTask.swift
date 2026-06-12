import Foundation
import SwiftData

/// The single source-of-truth model for the app.
///
/// Design decisions encoded in this model:
/// - State is derived from nullable timestamps (`doneAt`, `scheduledAt`,
///   `startedWaitingAt`) instead of a status column or boolean flags. This keeps
///   "when it happened" for free and avoids inconsistent flag combinations.
/// - Ordering lives on the model itself (`todayOrder`, `structuredOrder`), so no
///   separate ordering table is needed.
/// - Hierarchy is a self-reference (`parent` / `children`), allowing unlimited
///   nesting without a dedicated Project or Tag model.
@Model
final class TodayTask {
    /// Stable unique identity. `.unique` prevents duplicate rows for the same id.
    @Attribute(.unique) var id: UUID
    /// Human-readable task name shown in every area.
    var title: String
    /// Optional free-form note. Optional because most quick tasks need no detail.
    var notes: String?
    /// Estimated work time in minutes. Optional so an unestimated task is excluded
    /// from time totals rather than counted as zero.
    var estimatedMinutes: Int?

    /// Position in the Today column. Nullable because `nil` is how we represent
    /// "not in Today" without a separate flag.
    var todayOrder: Int?
    /// Position among siblings in the Structured tree. Non-optional because every
    /// task always has a place in the hierarchy.
    var structuredOrder: Int

    /// Completion time. Drives `isDone` and membership in the Done area.
    var doneAt: Date?
    /// Scheduled surfacing time. Drives `isScheduled` and the Scheduled list.
    var scheduledAt: Date?
    /// Time the task started waiting on a condition. Drives `isWaiting`.
    var startedWaitingAt: Date?
    /// Why the task is waiting (e.g. "waiting for reply"). Optional context.
    var waitingNote: String?

    /// Parent in the tree. `deleteRule: .nullify` with `inverse:` wires both sides
    /// of the self-relationship; deleting a parent detaches (not deletes) from
    /// this side.
    @Relationship(deleteRule: .nullify, inverse: \TodayTask.children)
    var parent: TodayTask?
    /// Child tasks. `deleteRule: .cascade` means deleting a task removes its whole
    /// subtree.
    @Relationship(deleteRule: .cascade)
    var children: [TodayTask]

    /// Creation timestamp (audit / stable default ordering).
    var createdAt: Date
    /// Last-modified timestamp (audit / future sync conflict resolution).
    var updatedAt: Date

    /// Creates a task. Every parameter has a default so callers usually pass only
    /// `title`.
    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        estimatedMinutes: Int? = nil,
        todayOrder: Int? = nil,
        structuredOrder: Int = 0,
        doneAt: Date? = nil,
        scheduledAt: Date? = nil,
        startedWaitingAt: Date? = nil,
        waitingNote: String? = nil,
        parent: TodayTask? = nil,
        children: [TodayTask] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        // Copy every argument into its matching stored property.
        self.id = id
        self.title = title
        self.notes = notes
        self.estimatedMinutes = estimatedMinutes
        self.todayOrder = todayOrder
        self.structuredOrder = structuredOrder
        self.doneAt = doneAt
        self.scheduledAt = scheduledAt
        self.startedWaitingAt = startedWaitingAt
        self.waitingNote = waitingNote
        self.parent = parent
        self.children = children
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Derived state (not persisted)

/// Convenience booleans derived from the nullable timestamps above. They are
/// computed (no backing storage), so SwiftData does not persist them.
extension TodayTask {
    /// In the Today column when it has a Today position.
    var isInToday: Bool { todayOrder != nil }
    /// Completed when it has a completion timestamp.
    var isDone: Bool { doneAt != nil }
    /// Scheduled when it has a scheduled timestamp.
    var isScheduled: Bool { scheduledAt != nil }
    /// Waiting when it has a waiting-start timestamp.
    var isWaiting: Bool { startedWaitingAt != nil }

    /// Children sorted by their position in the structured tree. The raw
    /// `children` relationship is unordered; this provides the display order
    /// used by StructuredAreaView and MinimapView.
    var sortedChildren: [TodayTask] {
        children.sorted { $0.structuredOrder < $1.structuredOrder }
    }

    /// True when the task is scheduled and its time has arrived (as of `date`).
    /// Drives the red "due" treatment in the Scheduled section. `date` is a
    /// parameter (instead of reading `.now` directly) so views can pass a
    /// ticking timeline date and tests can pass a fixed one.
    func isDue(asOf date: Date = .now) -> Bool {
        guard let scheduledAt else { return false }
        return scheduledAt <= date
    }

    /// True when this task sits anywhere below `possibleAncestor` in the tree.
    /// Walks the parent chain (cost bounded by tree depth). Used to reject
    /// drops that would create a cycle, e.g. moving a task into its own subtree.
    func isDescendant(of possibleAncestor: TodayTask) -> Bool {
        var current = parent
        while let node = current {
            if node.id == possibleAncestor.id { return true }
            current = node.parent
        }
        return false
    }

    /// The chain of ancestors from this task's parent up to the root. Used by
    /// the search dropdown (parent path display) and to expand collapsed
    /// ancestors when jumping to a search result.
    var ancestors: [TodayTask] {
        var chain: [TodayTask] = []
        var current = parent
        while let node = current {
            chain.append(node)
            current = node.parent
        }
        return chain
    }
}
