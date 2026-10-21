import CoreGraphics
import Testing
import XCloseCore

private let frame = CGRect(x: 10, y: 10, width: 14, height: 14)
private let armed = ArmedClick(pid: 9, appKey: .bundleID("com.apple.textedit"), appName: "TextEdit", buttonFrame: frame, armedAt: 0)

@Suite("Click sequencing")
struct ClickSequenceTrackerTests {
    @Test func unvalidatedPressPassesEverything() {
        var tracker = ClickSequenceTracker()
        do { let result = tracker.mouseDown(arm: nil); #expect(result == .pass) }
        #expect(tracker.mouseDragged() == .pass)
        let (disposition, outcome) = tracker.mouseUp(at: CGPoint(x: 15, y: 15))
        #expect(disposition == .pass)
        #expect(outcome == .notTracked)
    }

    @Test func validatedPressAndReleaseRequestsQuitOnce() {
        var tracker = ClickSequenceTracker()
        do { let result = tracker.mouseDown(arm: armed); #expect(result == .swallow) }
        let (disposition, outcome) = tracker.mouseUp(at: CGPoint(x: 15, y: 15))
        #expect(disposition == .swallow)
        #expect(outcome == .requestQuit(armed))
        // A stray second mouse-up is not a second request.
        do { let result = tracker.mouseUp(at: CGPoint(x: 15, y: 15)); #expect(result.1 == .notTracked) }
    }

    @Test func draggingAwayBeforeReleaseCancelsWithoutClosing() {
        var tracker = ClickSequenceTracker()
        _ = tracker.mouseDown(arm: armed)
        #expect(tracker.mouseDragged() == .swallow)
        let (disposition, outcome) = tracker.mouseUp(at: CGPoint(x: 200, y: 15))
        // Still swallowed: the app saw no mouse-down, so it must not see the up.
        #expect(disposition == .swallow)
        #expect(outcome == .cancelledDraggedAway(armed))
    }

    @Test func smallTrackpadJitterStillCounts() {
        var tracker = ClickSequenceTracker()
        _ = tracker.mouseDown(arm: armed)
        do { let result = tracker.mouseUp(at: CGPoint(x: 26, y: 8)); #expect(result.1 == .requestQuit(armed)) }
    }

    @Test func missedMouseUpIsDiscardedByNextPress() {
        var tracker = ClickSequenceTracker()
        _ = tracker.mouseDown(arm: armed)
        do { let result = tracker.mouseDown(arm: nil); #expect(result == .pass) }
        do { let result = tracker.mouseUp(at: CGPoint(x: 15, y: 15)); #expect(result == (.pass, .notTracked)) }
    }

    @Test func resetForgetsArmedPress() {
        var tracker = ClickSequenceTracker()
        _ = tracker.mouseDown(arm: armed)
        tracker.reset()
        do { let result = tracker.mouseUp(at: CGPoint(x: 15, y: 15)); #expect(result.1 == .notTracked) }
    }
}

@Suite("Quit requests")
struct QuitRequestTrackerTests {
    private func request(pid: Int32 = 9, at time: Double) -> QuitRequest {
        QuitRequest(pid: pid, appKey: .bundleID("com.apple.textedit"), appName: "TextEdit", requestedAt: time)
    }

    @Test func firstRequestIsSubmitted() {
        #expect(QuitRequestTracker().decide(pid: 9, now: 0) == .submit)
    }

    @Test func doubleClickDoesNotSendTwoRequests() {
        var tracker = QuitRequestTracker(duplicateWindow: 2)
        tracker.recordSubmitted(request(at: 100))
        #expect(tracker.decide(pid: 9, now: 100.3) == .suppressDuplicate)
        #expect(tracker.decide(pid: 10, now: 100.3) == .submit) // other apps unaffected
    }

    @Test func terminationIsConfirmedSeparatelyFromRequest() {
        var tracker = QuitRequestTracker()
        tracker.recordSubmitted(request(at: 100))
        #expect(tracker.isAwaitingTermination(pid: 9))
        do { let result = tracker.applicationTerminated(pid: 9, now: 101.5); #expect(result == .terminated(request(at: 100), after: 1.5)) }
        #expect(!tracker.isAwaitingTermination(pid: 9))
        do { let result = tracker.applicationTerminated(pid: 9, now: 102); #expect(result == nil) }
    }

    @Test func cancelledQuitTimesOutAndIsNeverRetriedAutomatically() {
        var tracker = QuitRequestTracker(duplicateWindow: 2, confirmationTimeout: 30)
        tracker.recordSubmitted(request(at: 100))
        do { let result = tracker.expire(now: 120); #expect(result.isEmpty) }
        #expect(tracker.nextExpiry == 130)
        do { let result = tracker.expire(now: 130); #expect(result == [.notConfirmed(request(at: 100))]) }
        #expect(tracker.pending.isEmpty)
        do { let result = tracker.expire(now: 200); #expect(result.isEmpty) }
    }

    @Test func userMayAskAgainAfterCancellingDialog() {
        var tracker = QuitRequestTracker(duplicateWindow: 2, confirmationTimeout: 30)
        tracker.recordSubmitted(request(at: 100))
        // User cancelled the save prompt and clicks red × again a few seconds later.
        #expect(tracker.decide(pid: 9, now: 105) == .submit)
    }

    @Test func failedSubmissionLeavesNothingPending() {
        var tracker = QuitRequestTracker()
        tracker.recordSubmitted(request(at: 100))
        tracker.recordSubmissionFailed(pid: 9)
        #expect(tracker.pending.isEmpty)
        #expect(tracker.decide(pid: 9, now: 100.1) == .submit)
    }

    @Test func unrelatedProcessExitIsIgnored() {
        var tracker = QuitRequestTracker()
        tracker.recordSubmitted(request(at: 100))
        do { let result = tracker.applicationTerminated(pid: 77, now: 101); #expect(result == nil) }
        #expect(tracker.isAwaitingTermination(pid: 9))
    }
}
