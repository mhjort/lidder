import Foundation
import QuartzCore

/// One lid-angle sample.
struct Sample: Equatable {
    let angle: Double      // degrees
    let velocity: Double   // degrees / second (smoothed, always >= 0)
    let ts: Double         // unix timestamp (seconds)

    var json: String {
        String(format: "{\"angle\":%.1f,\"velocity\":%.2f,\"ts\":%.3f}", angle, velocity, ts)
    }

    /// The sample as one Server-Sent Events message.
    var sseEvent: String {
        "data: \(json)\n\n"
    }
}

/// Turns a stream of raw angles into a smoothed angular velocity.
///
/// The smoothing mirrors the original LidAngleSensor app so that
/// gesture-style controls (flaps / slams) behave the same in the browser.
struct VelocityTracker {

    // Smoothing constants (ported from samhenrigold/LidAngleSensor).
    static let angleSmoothingFactor = 0.05
    static let velocitySmoothingFactor = 0.3
    static let movementThreshold = 0.5
    static let movementTimeout: TimeInterval = 0.05
    static let velocityDecay = 0.5
    static let additionalDecay = 0.8

    private var lastAngle = 0.0
    private var smoothedAngle = 0.0
    private var smoothedVelocity = 0.0
    private var lastUpdateTime: TimeInterval = 0
    private var lastMovementTime: TimeInterval = 0
    private var isFirstUpdate = true

    /// Feeds a raw angle read at monotonic time `now` (seconds) and returns
    /// the smoothed velocity in degrees / second.
    mutating func update(angle rawAngle: Double, at now: TimeInterval) -> Double {
        guard !isFirstUpdate else {
            lastAngle = rawAngle
            smoothedAngle = rawAngle
            lastUpdateTime = now
            lastMovementTime = now
            isFirstUpdate = false
            return 0
        }

        let dt = now - lastUpdateTime
        guard dt > 0, dt < 1.0 else {
            lastUpdateTime = now
            return smoothedVelocity
        }

        smoothedAngle =
            Self.angleSmoothingFactor * rawAngle
            + (1 - Self.angleSmoothingFactor) * smoothedAngle

        let delta = smoothedAngle - lastAngle
        let instantVelocity: Double
        if abs(delta) < Self.movementThreshold {
            instantVelocity = 0
        } else {
            instantVelocity = abs(delta / dt)
            lastAngle = smoothedAngle
        }

        if instantVelocity > 0 {
            smoothedVelocity =
                Self.velocitySmoothingFactor * instantVelocity
                + (1 - Self.velocitySmoothingFactor) * smoothedVelocity
            lastMovementTime = now
        } else {
            smoothedVelocity *= Self.velocityDecay
        }

        if now - lastMovementTime > Self.movementTimeout {
            smoothedVelocity *= Self.additionalDecay
        }

        lastUpdateTime = now
        return smoothedVelocity
    }
}

/// Polls the lid angle sensor at a fixed rate, computes a smoothed angular
/// velocity, and pushes each new `Sample` to subscribers.
public final class SensorPoller {

    private let sensor: LidAngleSensor
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "lidder.poller")

    private var timer: DispatchSourceTimer?
    private var subscribers: [UUID: (Sample) -> Void] = [:]
    private(set) var latest: Sample?
    private var velocity = VelocityTracker()

    public init(sensor: LidAngleSensor, hz: Double) {
        self.sensor = sensor
        self.interval = 1.0 / hz
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.interval)
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer
            timer.resume()
        }
    }

    // MARK: Subscriptions

    /// Registers a callback fired (on the poller queue) for every new sample.
    /// Returns a token to pass to `removeSubscriber`.
    func addSubscriber(_ handler: @escaping (Sample) -> Void) -> UUID {
        let token = UUID()
        queue.async { [weak self] in self?.subscribers[token] = handler }
        return token
    }

    func removeSubscriber(_ token: UUID) {
        queue.async { [weak self] in self?.subscribers.removeValue(forKey: token) }
    }

    // MARK: Polling

    private func poll() {
        let raw: Double
        do {
            raw = try sensor.readAngle()
        } catch {
            return  // transient read failure; try again next tick
        }

        let v = velocity.update(angle: raw, at: CACurrentMediaTime())
        let sample = Sample(angle: raw, velocity: v, ts: Date().timeIntervalSince1970)
        latest = sample
        for handler in subscribers.values {
            handler(sample)
        }
    }
}
