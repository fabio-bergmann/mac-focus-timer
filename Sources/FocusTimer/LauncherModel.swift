import AppKit
import Combine
import FocusTimerCore

/// State of the panel: what is typed, which row is selected, and whether the
/// timers or the settings are showing.
final class LauncherModel: ObservableObject {
    enum Mode {
        case launcher
        case settings
    }

    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            selectedID = nil
            pointerBaseline = NSEvent.mouseLocation
        }
    }
    @Published var mode: Mode = .launcher
    /// Nil selects the first row.
    @Published var selectedID: String?
    /// Bumped whenever the query field should take the keyboard again.
    @Published private(set) var focusToken = 0

    let settings: AppSettings
    let timer: TimerController
    let updates: UpdateService

    var dismiss: () -> Void = {}
    var willStartTimer: () -> Void = {}

    /// Where the pointer was when the list last changed. Rows only follow the
    /// pointer once it has moved, so a resting mouse can't steal the selection
    /// from the row Return is about to start.
    private var pointerBaseline = NSPoint.zero

    init(settings: AppSettings, timer: TimerController, updates: UpdateService) {
        self.settings = settings
        self.timer = timer
        self.updates = updates
    }

    func rows(now: Date = Date()) -> [LauncherRow] {
        Launcher.rows(query: query, presets: settings.presets, phase: timer.state.phase, now: now)
    }

    func selected(in rows: [LauncherRow]) -> LauncherRow? {
        rows.first { $0.id == selectedID } ?? rows.first
    }

    func prepareForShow(mode: Mode) {
        timer.acknowledge()
        query = ""
        selectedID = nil
        pointerBaseline = NSEvent.mouseLocation
        self.mode = mode
        focusToken += 1
    }

    func moveSelection(by delta: Int) {
        let rows = rows()
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selectedID } ?? 0
        selectedID = rows[min(rows.count - 1, max(0, current + delta))].id
    }

    func pointerMoved(over row: LauncherRow) {
        let pointer = NSEvent.mouseLocation
        guard abs(pointer.x - pointerBaseline.x) > 2 || abs(pointer.y - pointerBaseline.y) > 2 else { return }
        if selectedID != row.id { selectedID = row.id }
    }

    func activateSelected() {
        guard let row = selected(in: rows()) else {
            NSSound.beep()
            return
        }
        activate(row)
    }

    func activate(_ row: LauncherRow) {
        // Look the row up again: "until 15:30" is a different length by the
        // time Return is pressed than when it was drawn.
        let action = rows().first { $0.id == row.id }?.action ?? row.action
        switch action {
        case .start(let seconds, let label):
            willStartTimer()
            timer.start(seconds: seconds, label: label)
        case .add(let seconds):
            timer.add(seconds: seconds)
        case .pause:
            timer.pause()
        case .resume:
            timer.resume()
        case .stop:
            timer.stop()
        }
        dismiss()
    }

    /// Escape backs out one step at a time: settings, then the query, then the panel.
    func escape() {
        if mode == .settings {
            showLauncher()
        } else if !query.isEmpty {
            query = ""
        } else {
            dismiss()
        }
    }

    func showLauncher() {
        settings.isRecordingShortcut = false
        mode = .launcher
        focusToken += 1
    }

    func toggleSettings() {
        if mode == .settings {
            showLauncher()
        } else {
            mode = .settings
        }
    }
}
