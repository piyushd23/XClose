import Testing
import XCloseCore

@Suite("Operational state")
struct OperationalStateTests {
    @Test func pausedWinsOverEverything() {
        #expect(OperationalState.derive(isEnabled: false, hasAccessibility: true, tap: .running) == .paused)
        #expect(OperationalState.derive(isEnabled: false, hasAccessibility: false, tap: .stopped) == .paused)
    }

    @Test func permissionRequiredBeforeAnythingElse() {
        #expect(OperationalState.derive(isEnabled: true, hasAccessibility: false, tap: .running) == .permissionRequired)
    }

    @Test func onlyRunningTapIsOperational() {
        #expect(OperationalState.derive(isEnabled: true, hasAccessibility: true, tap: .running) == .operational)
        #expect(OperationalState.derive(isEnabled: true, hasAccessibility: true, tap: .starting) == .starting)
        #expect(OperationalState.derive(isEnabled: true, hasAccessibility: true, tap: .stopped) == .starting)
        #expect(OperationalState.derive(isEnabled: true, hasAccessibility: true, tap: .failedToStart) == .degraded(.eventTapUnavailable))
        #expect(OperationalState.derive(isEnabled: true, hasAccessibility: true, tap: .unstable) == .degraded(.eventTapUnstable))
    }

    @Test func onlyOperationalInterceptsClicks() {
        let states: [OperationalState] = [.paused, .permissionRequired, .starting, .degraded(.eventTapUnstable), .degraded(.eventTapUnavailable)]
        #expect(states.allSatisfy { !$0.interceptsClicks })
        #expect(OperationalState.operational.interceptsClicks)
        #expect(OperationalState.operational.title == "Active")
    }
}

@Suite("Tap planning and health")
struct TapPlannerTests {
    @Test func startsWhenEnabledAndTrusted() {
        #expect(TapPlanner.action(isEnabled: true, hasAccessibility: true, tap: .stopped) == .start)
        #expect(TapPlanner.action(isEnabled: true, hasAccessibility: true, tap: .running) == .none)
    }

    @Test func stopsImmediatelyWhenPausedOrRevoked() {
        #expect(TapPlanner.action(isEnabled: false, hasAccessibility: true, tap: .running) == .stop)
        #expect(TapPlanner.action(isEnabled: true, hasAccessibility: false, tap: .running) == .stop)
        #expect(TapPlanner.action(isEnabled: false, hasAccessibility: true, tap: .stopped) == .none)
    }

    @Test func doesNotFlapAfterFailure() {
        #expect(TapPlanner.action(isEnabled: true, hasAccessibility: true, tap: .failedToStart) == .none)
        #expect(TapPlanner.action(isEnabled: true, hasAccessibility: true, tap: .unstable) == .none)
        // Pausing a failed tap resets it so a later enable starts fresh.
        #expect(TapPlanner.action(isEnabled: false, hasAccessibility: true, tap: .unstable) == .stop)
    }

    @Test func repeatedTimeoutsWithinWindowMarkUnstable() {
        var monitor = TapHealthMonitor(window: 60, threshold: 3)
        do { let unstable = monitor.recordTimeout(now: 0); #expect(!unstable) }
        do { let unstable = monitor.recordTimeout(now: 10); #expect(!unstable) }
        do { let unstable = monitor.recordTimeout(now: 20); #expect(unstable) }
    }

    @Test func spreadOutTimeoutsAreTolerated() {
        var monitor = TapHealthMonitor(window: 60, threshold: 3)
        do { let unstable = monitor.recordTimeout(now: 0); #expect(!unstable) }
        do { let unstable = monitor.recordTimeout(now: 100); #expect(!unstable) }
        do { let unstable = monitor.recordTimeout(now: 200); #expect(!unstable) }
    }
}

@Suite("Bounded storage")
struct BoundedStorageTests {
    @Test func logKeepsNewestEntriesWithinCapacity() {
        var log = BoundedLog<Int>(capacity: 3)
        for value in 1...10 { log.append(value) }
        #expect(log.elements == [8, 9, 10])
    }

    @Test func penaltyExpires() {
        var box = PenaltyBox(duration: 5)
        box.penalize(4, now: 100)
        #expect(box.isPenalized(4, now: 104))
        #expect(!box.isPenalized(4, now: 105.1))
        #expect(!box.isPenalized(5, now: 101))
    }
}
