import FocusTimerCore
import UserNotifications

/// Posts the "timer finished" notification. The sound is played by the app
/// itself, so it works even when notifications are switched off.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    // UNUserNotificationCenter traps outside an app bundle (`swift run`).
    private let center: UNUserNotificationCenter? = Bundle.main.bundleIdentifier == nil ? nil : .current()

    override init() {
        super.init()
        center?.delegate = self
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func timerFinished(seconds: Int, label: String?) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = label ?? "Timer finished"
        content.body = "\(DurationFormat.spoken(seconds)) is up."
        center.add(UNNotificationRequest(identifier: "timer-finished", content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
