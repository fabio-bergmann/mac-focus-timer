import AppKit
import Combine
import FocusTimerCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let timer = TimerController()
    private let updates = UpdateService()
    private let notifier = Notifier()
    private let hotKey = HotKey()
    private let glow = ScreenGlow()
    private var statusItem: StatusItemController?
    private var panel: PanelController?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if anotherInstanceIsRunning {
            NSApp.terminate(nil)
            return
        }

        let model = LauncherModel(settings: settings, timer: timer, updates: updates)
        model.willStartTimer = { [notifier] in notifier.requestAuthorization() }
        let panel = PanelController(model: model)
        self.panel = panel

        let statusItem = StatusItemController(settings: settings, timer: timer)
        statusItem.onClick = { panel.toggle(fromMenuBar: true) }
        statusItem.onShowSettings = { panel.show(settings: true) }
        statusItem.onDragStart = { panel.hide() }
        statusItem.willStartTimer = { [notifier] in notifier.requestAuthorization() }
        self.statusItem = statusItem

        hotKey.onPress = { panel.toggle() }
        // Recording a new shortcut has to release the current one first, or the
        // system swallows the keystroke before the recorder sees it.
        settings.$hotKey.combineLatest(settings.$isRecordingShortcut)
            .sink { [weak self] combo, isRecording in
                guard let self else { return }
                let registered = self.hotKey.register(isRecording ? nil : combo)
                self.settings.hotKeyUnavailable = !registered
            }
            .store(in: &subscriptions)

        timer.onFinish = { [weak self] seconds, label in
            guard let self else { return }
            self.notifier.timerFinished(seconds: seconds, label: label)
            if self.settings.soundEnabled { NSSound(named: "Glass")?.play() }
            if self.settings.glowEnabled { self.glow.play() }
        }
    }

    private var anotherInstanceIsRunning: Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains { $0 != .current }
    }
}
