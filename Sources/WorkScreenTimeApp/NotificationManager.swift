import Foundation
import UserNotifications
import WorkScreenTimeCore

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func scheduleWarnings(config: AppConfig, engine: ScheduleEngine, now: Date = Date()) {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        let requests = engine.upcomingWarningDates(from: now, config: config, limit: 14).prefix(14).map { item in
            let content = UNMutableNotificationContent()
            content.title = "Downtime starts soon"
            content.body = "Your stop-working window starts at \(formatter.string(from: item.window.start))."
            content.sound = .default

            let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day, .hour, .minute], from: item.warningDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            return UNNotificationRequest(identifier: warningIdentifier(for: item.window.id), content: content, trigger: trigger)
        }

        center.getPendingNotificationRequests { [center] pending in
            let oldWarningIDs = pending
                .map(\.identifier)
                .filter { $0.hasPrefix("downtime-warning-") }
            center.removePendingNotificationRequests(withIdentifiers: oldWarningIDs)

            for request in requests {
                center.add(request)
            }
        }
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "Test notification"
        content.body = "Notifications are working."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: nil))
    }

    func notifyGrace() {
        let content = UNMutableNotificationContent()
        content.title = "Activity detected during downtime"
        content.body = "30 second grace period — enforcement begins after 1 minute of continued activity."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "enforcement-grace-\(UUID().uuidString)", content: content, trigger: nil))
    }

    func notifyResuming() {
        let content = UNMutableNotificationContent()
        content.title = "Resuming — 30 second grace period"
        content.body = "Enforcement will kick in after 30 seconds if you're still active."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "resume-grace", content: content, trigger: nil))
    }

    func notifyInputDetected() {
        let content = UNMutableNotificationContent()
        content.title = "Downtime active"
        content.body = "Input detected during downtime. The screen prompt will appear in 1 minute if you keep working."
        content.sound = .default

        center.add(UNNotificationRequest(identifier: "input-warning-\(UUID().uuidString)", content: content, trigger: nil))
    }

    func notifySnoozed(until date: Date) {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        let content = UNMutableNotificationContent()
        content.title = "Snoozed"
        content.body = "Snoozed until \(formatter.string(from: date))."
        content.sound = .default

        center.add(UNNotificationRequest(identifier: "snoozed-\(UUID().uuidString)", content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func warningIdentifier(for windowID: String) -> String {
        "downtime-warning-\(windowID)"
    }
}
