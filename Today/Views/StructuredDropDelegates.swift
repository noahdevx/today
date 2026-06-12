import SwiftData
import SwiftUI

/// Which part of a row a drag is hovering over - and so where the dragged
/// task would land relative to the row's task: above it (previous sibling),
/// nested inside it (child), or below it (next sibling).
enum StructuredDropZone {
    case before
    case after
    case child
}

/// Drop delegate for a single structured row. Tracks the hover zone while a
/// drag passes over the row (driving the insertion indicator) and performs
/// the matching tree move on drop.
///
/// The dragged task is identified through `SelectionEngine.draggedTaskID`
/// (set by the drag source): unlike decoding the NSItemProvider payload this
/// is synchronous, so validation and zone feedback can run in `dropUpdated`.
/// `TaskManager.moveStructuredTask` re-checks cycles on the actual move.
@MainActor
struct StructuredRowDropDelegate: DropDelegate {
    /// The task whose row is being hovered / dropped on.
    let target: TodayTask
    /// Measured row height, for the 3-zone vertical split.
    let rowHeight: CGFloat
    /// Shared engine carrying the in-flight dragged task ID.
    let engine: SelectionEngine
    /// Context for the move mutation.
    let context: ModelContext
    /// Zone under the pointer, bound to the row's feedback overlays.
    @Binding var hoverZone: StructuredDropZone?

    /// Splits the row into before (top quarter), child (middle half), and
    /// after (bottom quarter) zones.
    private func zone(at location: CGPoint) -> StructuredDropZone {
        guard rowHeight > 0 else { return .child }
        let fraction = location.y / rowHeight
        if fraction < 0.25 { return .before }
        if fraction > 0.75 { return .after }
        return .child
    }

    /// The dragged task, resolved through the engine. Nil when the drag does
    /// not come from inside the app.
    private var draggedTask: TodayTask? {
        guard let draggedID = engine.draggedTaskID else { return nil }
        return TaskManager.findTask(id: draggedID, in: context)
    }

    /// A drop is acceptable unless it targets the dragged task itself or a
    /// row inside the dragged task's own subtree (which would create a cycle).
    func validateDrop(info: DropInfo) -> Bool {
        guard let dragged = draggedTask else { return false }
        guard dragged.id != target.id else { return false }
        return !target.isDescendant(of: dragged)
    }

    func dropEntered(info: DropInfo) {
        hoverZone = zone(at: info.location)
    }

    /// Continuously updates the zone indicator while the drag moves.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        hoverZone = zone(at: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        hoverZone = nil
    }

    /// Performs the tree move matching the final zone.
    func performDrop(info: DropInfo) -> Bool {
        let zone = zone(at: info.location)
        hoverZone = nil
        guard let dragged = draggedTask else { return false }
        engine.draggedTaskID = nil

        switch zone {
        case .before:
            TaskManager.moveStructuredTask(dragged, before: target, in: context)
        case .after:
            TaskManager.moveStructuredTask(dragged, after: target, in: context)
        case .child:
            TaskManager.moveStructuredTask(dragged, toParent: target, in: context)
            // Reveal the freshly nested child.
            engine.collapsedIDs.remove(target.id)
        }
        return true
    }
}

/// Drop delegate for the empty area below the tree: moves the dragged task to
/// the end of the root level. This keeps "un-nest entirely" reachable even
/// when the tree is dense.
@MainActor
struct StructuredRootTailDropDelegate: DropDelegate {
    /// Shared engine carrying the in-flight dragged task ID.
    let engine: SelectionEngine
    /// Context for the move mutation.
    let context: ModelContext
    /// Targeting flag bound to the tail area's insertion line.
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        engine.draggedTaskID != nil
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let draggedID = engine.draggedTaskID,
              let dragged = TaskManager.findTask(id: draggedID, in: context) else { return false }
        engine.draggedTaskID = nil
        TaskManager.moveStructuredTask(dragged, toParent: nil, in: context)
        return true
    }
}
