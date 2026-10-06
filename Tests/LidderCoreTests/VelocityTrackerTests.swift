import Testing
@testable import LidderCore

@Suite struct VelocityTrackerTests {

    @Test func firstSampleHasZeroVelocity() {
        var tracker = VelocityTracker()
        #expect(tracker.update(angle: 100, at: 10) == 0)
    }

    @Test func stillLidHasZeroVelocity() {
        var tracker = VelocityTracker()
        for i in 0..<30 {
            #expect(tracker.update(angle: 100, at: Double(i) / 30) == 0)
        }
    }

    @Test func movementProducesSmoothedVelocity() {
        var tracker = VelocityTracker()
        _ = tracker.update(angle: 100, at: 0)
        // Smoothed angle: 0.05 * 150 + 0.95 * 100 = 102.5, so 2.5° in 0.1 s
        // is 25°/s, and the smoothed velocity is 0.3 * 25 = 7.5°/s.
        let v = tracker.update(angle: 150, at: 0.1)
        #expect(abs(v - 7.5) < 1e-9)
    }

    @Test func closingTheLidGivesPositiveVelocity() {
        var tracker = VelocityTracker()
        _ = tracker.update(angle: 150, at: 0)
        #expect(tracker.update(angle: 100, at: 0.1) > 0)
    }

    @Test func tinyJitterIsIgnored() {
        var tracker = VelocityTracker()
        _ = tracker.update(angle: 100, at: 0)
        // 0.05 * 105 + 0.95 * 100 = 100.25: below the 0.5° movement threshold.
        #expect(tracker.update(angle: 105, at: 0.1) == 0)
    }

    @Test func velocityDecaysAfterTheLidStops() {
        var tracker = VelocityTracker()
        var t = 0.0
        var angle = 60.0
        _ = tracker.update(angle: angle, at: t)
        // Swing the lid open quickly...
        var peak = 0.0
        for _ in 0..<15 {
            t += 1.0 / 30
            angle += 4
            peak = max(peak, tracker.update(angle: angle, at: t))
        }
        #expect(peak > 10)
        // ...then hold it still. The angle smoothing is slow, so the smoothed
        // angle keeps catching up (and registering movement) for a while.
        var v = peak
        for _ in 0..<150 {
            t += 1.0 / 30
            v = tracker.update(angle: angle, at: t)
        }
        #expect(v < 0.01)
    }

    @Test func longGapKeepsPreviousVelocity() {
        var tracker = VelocityTracker()
        _ = tracker.update(angle: 100, at: 0)
        let before = tracker.update(angle: 150, at: 0.1)
        // A gap of a second or more (e.g. the machine slept) is not treated
        // as movement.
        #expect(tracker.update(angle: 10, at: 5) == before)
    }
}
