import AppKit
import Combine
import FocusTimerCore

/// Owns the one timer: keeps it in UserDefaults so it survives a relaunch or an
/// update, and ticks once a second while there is something to redraw.
final class TimerController: ObservableObject {
    @Published private(set) var state: TimerState
    /// Moves forward on every tick, so views recompute the time left.
    @Published private(set) var now = Date()

    var onFinish: ((_ seconds: Int, _ label: String?) -> Void)?

    static let stateKey = "timerState"
    private let defaults: UserDefaults
    private var ticker: Timer?
    private var activity: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var restored = defaults.data(forKey: Self.stateKey)
            .flatMap { try? JSONDecoder().decode(TimerState.self, from: $0) } ?? TimerState()
        // A timer that ran out while the app was closed comes back as finished.
        _ = restored.tick(now: Date())
        state = restored

        // Timers don't fire during sleep, so catch up the moment the Mac wakes.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.tick() }
        schedule()
    }

    deinit {
        ticker?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    func start(seconds: Int, label: String?) { mutate { $0.start(seconds: seconds, label: label, now: $1) } }
    func pause() { mutate { $0.pause(now: $1) } }
    func resume() { mutate { $0.resume(now: $1) } }
    func add(seconds: Int) { mutate { $0.add(seconds: seconds, now: $1) } }
    func stop() { mutate { state, _ in state.stop() } }
    func acknowledge() { mutate { state, _ in state.acknowledge() } }

    private func mutate(_ change: (inout TimerState, Date) -> Void) {
        let date = Date()
        var next = state
        change(&next, date)
        now = date
        guard next != state else { return }
        state = next
        persist()
        schedule()
    }

    private func tick() {
        let date = Date()
        var next = state
        let finished = next.tick(now: date)
        now = date
        if next != state {
            state = next
            persist()
        }
        if finished, case .finished(_, let total, let label) = next.phase {
            onFinish?(Int(total), label)
        }
        schedule()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.stateKey)
    }

    private func schedule() {
        ticker?.invalidate()
        ticker = nil

        var delay: TimeInterval?
        switch state.phase {
        case .running(let end, _, _):
            // Land just after each whole second of remaining time, which is
            // when the displayed number changes.
            let remaining = end.timeIntervalSinceNow
            delay = max(0.02, remaining - remaining.rounded(.down) + 0.01)
        case .finished(let at, _, _) where Date().timeIntervalSince(at) < PillContent.pulseDuration + 1:
            delay = 1
        case .idle, .paused, .finished:
            break
        }

        if let delay {
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
        updateActivity()
    }

    /// App Nap would otherwise stretch the ticks of a windowless app to many seconds.
    private func updateActivity() {
        let isRunning = state.endDate != nil
        if isRunning, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Counting down a timer"
            )
        } else if !isRunning, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
    }
}
