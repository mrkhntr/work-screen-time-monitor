import Foundation

public struct ScheduleEngine: Sendable {
    private static let secondsPerMinute: TimeInterval = 60
    private static let secondsPerDay: TimeInterval = 86_400

    public var calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    public func activeWindow(at date: Date, config: AppConfig) -> DowntimeWindow? {
        for offset in -1...0 {
            guard
                let candidateDay = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)),
                let weekday = Weekday(rawValue: calendar.component(.weekday, from: candidateDay)),
                let schedule = config.schedule(for: weekday),
                schedule.isEnabled
            else {
                continue
            }

            let window = downtimeWindow(for: schedule, on: candidateDay)
            if date >= window.start && date < window.end {
                return window
            }
        }

        return nil
    }

    public func downtimeWindow(for schedule: DaySchedule, on day: Date) -> DowntimeWindow {
        let dayStart = calendar.startOfDay(for: day)
        let start = date(on: dayStart, time: schedule.start)
        var end = date(on: dayStart, time: schedule.end)

        if end <= start {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(Self.secondsPerDay)
        }

        let id = "\(dateKey(for: start))-\(schedule.weekday.displayName.lowercased())-\(schedule.start.storageString)-\(schedule.end.storageString)"
        return DowntimeWindow(id: id, weekday: schedule.weekday, start: start, end: end)
    }

    public func upcomingWarningDates(from date: Date, config: AppConfig, limit: Int = 14) -> [(window: DowntimeWindow, warningDate: Date)] {
        guard limit > 0 else {
            return []
        }

        var results: [(DowntimeWindow, Date)] = []
        let searchStart = calendar.startOfDay(for: date)

        for dayOffset in 0..<limit {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: searchStart),
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
                  let schedule = config.schedule(for: weekday),
                  schedule.isEnabled else {
                continue
            }

            let window = downtimeWindow(for: schedule, on: day)
            let warningDate = window.start.addingTimeInterval(-Self.seconds(minutes: max(config.warningLeadMinutes, 0)))
            if warningDate > date {
                results.append((window, warningDate))
            }
        }

        return results
    }

    public func dateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    public func escalationState(snoozeCount: Int, config: AppConfig, quote: String?) -> EscalationState {
        let snoozeCount = max(0, snoozeCount)
        let title: String
        let baseMessage: String

        switch snoozeCount {
        case 0:
            title = "Time to stop working"
            baseMessage = quote?.nilIfBlank ?? "You have done enough for today."
        case 1:
            title = "You already asked for \(Self.minutesDescription(max(config.snoozeMinutes, 1)))"
            baseMessage = "Close the loop and protect the rest of your night."
        case 2:
            title = "This is the second snooze"
            baseMessage = "Hold to unlock the next action before continuing."
        default:
            title = "You are past the boundary you set"
            baseMessage = "To snooze or dismiss, unlock the action and write why continuing makes sense."
        }

        return EscalationState(
            snoozeCount: snoozeCount,
            title: title,
            message: baseMessage,
            requiresHold: Self.hasReachedEscalationThreshold(snoozeCount, threshold: config.escalation.holdRequiredAtSnoozeCount),
            requiresPhrase: Self.hasReachedEscalationThreshold(snoozeCount, threshold: config.escalation.phraseRequiredAtSnoozeCount),
            requiresReason: Self.hasReachedEscalationThreshold(snoozeCount, threshold: config.escalation.reasonRequiredAtSnoozeCount)
        )
    }

    private func date(on day: Date, time: TimeOfDay) -> Date {
        calendar.date(
            bySettingHour: time.hour,
            minute: time.minute,
            second: 0,
            of: day
        ) ?? day.addingTimeInterval(TimeInterval(time.minutesAfterMidnight * 60))
    }

    private static func seconds(minutes: Int) -> TimeInterval {
        TimeInterval(minutes) * secondsPerMinute
    }

    private static func minutesDescription(_ minutes: Int) -> String {
        minutes == 1 ? "1 more minute" : "\(minutes) more minutes"
    }

    private static func hasReachedEscalationThreshold(_ snoozeCount: Int, threshold: Int) -> Bool {
        snoozeCount >= max(0, threshold)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
