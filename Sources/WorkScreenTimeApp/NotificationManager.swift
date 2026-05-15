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

    func scheduleWarnings(config: AppConfig) {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        let requests = config.schedules.filter(\.isEnabled).map { schedule in
            let warning = weeklyWarningTime(for: schedule, leadMinutes: config.warningLeadMinutes)
            let startDate = Calendar.autoupdatingCurrent.date(
                bySettingHour: schedule.start.hour,
                minute: schedule.start.minute,
                second: 0,
                of: Date()
            ) ?? Date()

            let content = UNMutableNotificationContent()
            content.title = "Downtime starts soon"
            content.body = "Your stop-working window starts at \(formatter.string(from: startDate))."
            content.sound = .default

            var components = DateComponents()
            components.weekday = warning.weekday.rawValue
            components.hour = warning.time.hour
            components.minute = warning.time.minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            return UNNotificationRequest(identifier: warningIdentifier(for: schedule.weekday), content: content, trigger: trigger)
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

    private func warningIdentifier(for weekday: Weekday) -> String {
        "downtime-warning-\(weekday.rawValue)"
    }

    private func weeklyWarningTime(for schedule: DaySchedule, leadMinutes: Int) -> (weekday: Weekday, time: TimeOfDay) {
        let minutesPerDay = 24 * 60
        let lead = max(leadMinutes, 0)
        let rawWarningMinutes = schedule.start.minutesAfterMidnight - lead
        let dayOffset = floorDiv(rawWarningMinutes, minutesPerDay)
        let warningMinutes = mod(rawWarningMinutes, minutesPerDay)
        let weekday = weekday(schedule.weekday, offsetBy: dayOffset)
        return (weekday, TimeOfDay(minutesAfterMidnight: warningMinutes))
    }

    private func weekday(_ weekday: Weekday, offsetBy dayOffset: Int) -> Weekday {
        let zeroBased = weekday.rawValue - 1
        let shifted = mod(zeroBased + dayOffset, Weekday.allCases.count)
        return Weekday(rawValue: shifted + 1) ?? weekday
    }

    private func floorDiv(_ value: Int, _ divisor: Int) -> Int {
        precondition(divisor > 0)
        return Int(floor(Double(value) / Double(divisor)))
    }

    private func mod(_ value: Int, _ divisor: Int) -> Int {
        precondition(divisor > 0)
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
