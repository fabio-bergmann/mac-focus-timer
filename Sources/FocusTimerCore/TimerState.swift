import Foundation

public enum TimerPhase: Equatable, Codable {
    case idle
    case running(end: Date, total: TimeInterval, label: String?)
    case paused(remaining: TimeInterval, total: TimeInterval, label: String?)
    /// Ran out a moment ago. Shown briefly, then back to idle.
    case finished(at: Date, total: TimeInterval, label: String?)

    public var isActive: Bool {
        switch self {
        case .running, .paused: true
        case .idle, .finished: false
        }
    }
}

/// The one timer the app runs. Time is always passed in, so the end is a wall
/// clock date: sleep, relaunches and late ticks can't make it drift.
public struct TimerState: Equatable, Codable {
    /// How long the menu bar item marks a finished timer before it clears.
    public static let finishedDisplay: TimeInterval = 5

    public private(set) var phase: TimerPhase = .idle

    public init() {}

    public var isActive: Bool { phase.isActive }

    public var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    public var label: String? {
        switch phase {
        case .idle: nil
        case .running(_, _, let label), .paused(_, _, let label), .finished(_, _, let label): label
        }
    }

    public var endDate: Date? {
        if case .running(let end, _, _) = phase { return end }
        return nil
    }

    /// Time left on a running or paused timer.
    public func remaining(now: Date) -> TimeInterval? {
        switch phase {
        case .running(let end, _, _): max(0, end.timeIntervalSince(now))
        case .paused(let remaining, _, _): remaining
        case .idle, .finished: nil
        }
    }

    /// Share of the timer still to go, 1 at the start and 0 at the end.
    public func fraction(now: Date) -> Double {
        switch phase {
        case .running(_, let total, _), .paused(_, let total, _):
            guard total > 0, let remaining = remaining(now: now) else { return 0 }
            return min(1, max(0, remaining / total))
        case .finished: return 1
        case .idle: return 0
        }
    }

    public mutating func start(seconds: Int, label: String?, now: Date) {
        let total = TimeInterval(max(1, seconds))
        phase = .running(end: now.addingTimeInterval(total), total: total, label: label)
    }

    public mutating func pause(now: Date) {
        guard case .running(let end, let total, let label) = phase else { return }
        phase = .paused(remaining: max(0, end.timeIntervalSince(now)), total: total, label: label)
    }

    public mutating func resume(now: Date) {
        guard case .paused(let remaining, let total, let label) = phase else { return }
        phase = .running(end: now.addingTimeInterval(remaining), total: total, label: label)
    }

    /// Extends the timer; the total grows with it so the bar never overfills.
    public mutating func add(seconds: Int, now: Date) {
        let extra = TimeInterval(seconds)
        switch phase {
        case .running(let end, let total, let label):
            phase = .running(end: end.addingTimeInterval(extra), total: total + extra, label: label)
        case .paused(let remaining, let total, let label):
            phase = .paused(remaining: remaining + extra, total: total + extra, label: label)
        case .idle, .finished:
            break
        }
    }

    public mutating func stop() {
        phase = .idle
    }

    /// Clears a finished timer once it has been seen.
    public mutating func acknowledge() {
        if case .finished = phase { phase = .idle }
    }

    /// Moves a running timer whose end has passed to `.finished`. Returns true
    /// on that transition only. The finish is dated from when it is noticed,
    /// not from the end time, so a timer that ran out while the Mac slept is
    /// still marked for a moment after it wakes.
    public mutating func tick(now: Date) -> Bool {
        guard case .running(let end, let total, let label) = phase, now >= end else { return false }
        phase = .finished(at: now, total: total, label: label)
        return true
    }

    /// Returns a finished timer to idle once it has been marked for long
    /// enough. True when it did.
    public mutating func expireFinished(now: Date) -> Bool {
        guard case .finished(let at, _, _) = phase, now.timeIntervalSince(at) >= Self.finishedDisplay else { return false }
        phase = .idle
        return true
    }
}
