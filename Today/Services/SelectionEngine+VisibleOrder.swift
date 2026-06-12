import Foundation
import SwiftData

/// Visible-order computation for keyboard navigation.
///
/// Split out of `SelectionEngine.swift` to keep both files comfortably small.
/// Each area's order mirrors the corresponding area view's `@Query` (same
/// predicate and sort) so navigation matches what is on screen.
extension SelectionEngine {
    /// The IDs of the tasks currently visible in the given area, top to
    /// bottom.
    func visibleTaskIDs(in area: AreaKind, context: ModelContext) -> [UUID] {
        switch area {
        case .today:
            let descriptor = FetchDescriptor<TodayTask>(
                predicate: #Predicate { $0.todayOrder != nil && $0.doneAt == nil },
                sortBy: [SortDescriptor(\.todayOrder)]
            )
            return fetchIDs(descriptor, context: context)

        case .done:
            // Same "completed today" boundary as DoneAreaView.
            let startOfToday = Calendar.current.startOfDay(for: .now)
            let descriptor = FetchDescriptor<TodayTask>(
                predicate: #Predicate { task in
                    if let doneAt = task.doneAt {
                        return doneAt >= startOfToday
                    } else {
                        return false
                    }
                },
                sortBy: [SortDescriptor(\.doneAt, order: .reverse)]
            )
            return fetchIDs(descriptor, context: context)

        case .structured:
            return structuredVisibleIDs(context: context)

        case .scheduled:
            let descriptor = FetchDescriptor<TodayTask>(
                predicate: #Predicate { $0.scheduledAt != nil && $0.doneAt == nil },
                sortBy: [SortDescriptor(\.scheduledAt)]
            )
            return fetchIDs(descriptor, context: context)

        case .waiting:
            let descriptor = FetchDescriptor<TodayTask>(
                predicate: #Predicate { $0.startedWaitingAt != nil && $0.doneAt == nil },
                sortBy: [SortDescriptor(\.startedWaitingAt)]
            )
            return fetchIDs(descriptor, context: context)
        }
    }

    /// Runs a fetch and reduces the result to IDs (navigation only needs
    /// identity and order).
    private func fetchIDs(_ descriptor: FetchDescriptor<TodayTask>, context: ModelContext) -> [UUID] {
        ((try? context.fetch(descriptor)) ?? []).map(\.id)
    }

    /// Depth-first walk of the structured tree in display order, skipping the
    /// subtrees of collapsed nodes - exactly the rows StructuredAreaView
    /// renders.
    private func structuredVisibleIDs(context: ModelContext) -> [UUID] {
        let descriptor = FetchDescriptor<TodayTask>(
            sortBy: [SortDescriptor(\.structuredOrder)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        let roots = all.filter { $0.parent == nil }

        var result: [UUID] = []
        // Local recursion keeps the traversal logic next to its only caller.
        func visit(_ task: TodayTask) {
            result.append(task.id)
            guard !collapsedIDs.contains(task.id) else { return }
            for child in task.sortedChildren {
                visit(child)
            }
        }
        for root in roots {
            visit(root)
        }
        return result
    }
}
