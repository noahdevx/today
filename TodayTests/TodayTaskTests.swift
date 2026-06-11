import Foundation
import Testing
@testable import Today

/// Unit tests for the pure logic of `TodayTask`: initializer defaults and the
/// derived-state computed properties. These require no database.
@Suite("TodayTask logic")
struct TodayTaskTests {
    /// B1: a task created with only a title gets the documented defaults.
    @Test("init applies the documented defaults when only a title is given")
    func initAppliesDefaults() {
        let before = Date.now
        let task = TodayTask(title: "Write tests")

        #expect(task.title == "Write tests")
        #expect(task.todayOrder == nil)
        #expect(task.structuredOrder == 0)
        #expect(task.notes == nil)
        #expect(task.estimatedMinutes == nil)
        #expect(task.doneAt == nil)
        #expect(task.scheduledAt == nil)
        #expect(task.startedWaitingAt == nil)
        #expect(task.waitingNote == nil)
        #expect(task.children.isEmpty)
        #expect(task.createdAt >= before)
        #expect(task.updatedAt >= before)
    }

    /// B2: isInToday tracks todayOrder.
    @Test("isInToday is true exactly when todayOrder is set", arguments: [nil, 0, 3] as [Int?])
    func isInTodayTracksTodayOrder(order: Int?) {
        let task = TodayTask(title: "t", todayOrder: order)
        #expect(task.isInToday == (order != nil))
    }

    /// B2: isDone tracks doneAt.
    @Test("isDone is true exactly when doneAt is set", arguments: [nil, Date.now] as [Date?])
    func isDoneTracksDoneAt(doneAt: Date?) {
        let task = TodayTask(title: "t", doneAt: doneAt)
        #expect(task.isDone == (doneAt != nil))
    }

    /// B2: isScheduled tracks scheduledAt.
    @Test("isScheduled is true exactly when scheduledAt is set", arguments: [nil, Date.now] as [Date?])
    func isScheduledTracksScheduledAt(scheduledAt: Date?) {
        let task = TodayTask(title: "t", scheduledAt: scheduledAt)
        #expect(task.isScheduled == (scheduledAt != nil))
    }

    /// B2: isWaiting tracks startedWaitingAt.
    @Test("isWaiting is true exactly when startedWaitingAt is set", arguments: [nil, Date.now] as [Date?])
    func isWaitingTracksStartedWaitingAt(startedWaitingAt: Date?) {
        let task = TodayTask(title: "t", startedWaitingAt: startedWaitingAt)
        #expect(task.isWaiting == (startedWaitingAt != nil))
    }

    /// isDue: only scheduled tasks whose time has passed (or is exactly now)
    /// are due. The scheduled time is given as an offset in seconds from the
    /// reference date; nil = not scheduled.
    @Test(
        "isDue is true only when the scheduled time has arrived",
        arguments: [
            (nil, false),   // not scheduled -> never due
            (-60, true),    // one minute ago -> due
            (0, true),      // exactly now -> due
            (60, false)     // one minute ahead -> not due yet
        ] as [(Int?, Bool)]
    )
    func isDueChecksScheduledTime(offsetSeconds: Int?, expected: Bool) {
        let now = Date.now
        let scheduledAt = offsetSeconds.map { now.addingTimeInterval(TimeInterval($0)) }
        let task = TodayTask(title: "t", scheduledAt: scheduledAt)
        #expect(task.isDue(asOf: now) == expected)
    }
}
