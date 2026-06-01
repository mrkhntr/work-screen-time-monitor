import Foundation

public enum Weekday: Int, Codable, CaseIterable, Identifiable, Sendable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }
}

public struct TimeOfDay: Codable, Equatable, Sendable {
    public var hour: Int
    public var minute: Int

    private enum CodingKeys: String, CodingKey {
        case hour
        case minute
    }

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public init(minutesAfterMidnight: Int) {
        let boundedMinutes = min(max(minutesAfterMidnight, 0), Self.minutesPerDay - 1)
        self.init(hour: boundedMinutes / 60, minute: boundedMinutes % 60)
    }

    public init?(storageString: String) {
        let parts = storageString.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }

        self.init(hour: hour, minute: minute)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hour = try container.decode(Int.self, forKey: .hour)
        let minute = try container.decode(Int.self, forKey: .minute)
        self.init(hour: hour, minute: minute)
    }

    public var minutesAfterMidnight: Int {
        hour * 60 + minute
    }

    public var storageString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    private static let minutesPerDay = 24 * 60
}

public struct DaySchedule: Codable, Equatable, Sendable {
    public var weekday: Weekday
    public var isEnabled: Bool
    public var start: TimeOfDay
    public var end: TimeOfDay

    public init(weekday: Weekday, isEnabled: Bool, start: TimeOfDay, end: TimeOfDay) {
        self.weekday = weekday
        self.isEnabled = isEnabled
        self.start = start
        self.end = end
    }
}

public struct EscalationConfig: Codable, Equatable, Sendable {
    public var holdRequiredAtSnoozeCount: Int
    public var phraseRequiredAtSnoozeCount: Int
    public var reasonRequiredAtSnoozeCount: Int
    public var confirmationPhrase: String

    public init(
        holdRequiredAtSnoozeCount: Int = 2,
        phraseRequiredAtSnoozeCount: Int = 3,
        reasonRequiredAtSnoozeCount: Int = 3,
        confirmationPhrase: String = "I am done for today"
    ) {
        self.holdRequiredAtSnoozeCount = holdRequiredAtSnoozeCount
        self.phraseRequiredAtSnoozeCount = phraseRequiredAtSnoozeCount
        self.reasonRequiredAtSnoozeCount = reasonRequiredAtSnoozeCount
        self.confirmationPhrase = confirmationPhrase
    }
}

public struct AccountabilityWebhookHeader: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var isEnabled: Bool
    public var name: String
    public var value: String

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        name: String = "",
        value: String = ""
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.name = name
        self.value = value
    }
}

public struct AccountabilityWebhookBodyField: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var isEnabled: Bool
    public var key: String
    public var value: String

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        key: String = "",
        value: String = ""
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.key = key
        self.value = value
    }
}

public struct AccountabilityWebhookConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var endpointURLString: String
    public var bearerToken: String
    public var apiKey: String
    public var headers: [AccountabilityWebhookHeader]
    public var messageTemplate: String
    public var bodyFields: [AccountabilityWebhookBodyField]
    public var snoozeNotifyThreshold: Int

    public init(
        isEnabled: Bool = false,
        endpointURLString: String = "",
        bearerToken: String = "",
        apiKey: String = "",
        headers: [AccountabilityWebhookHeader] = [],
        messageTemplate: String = "I {{event}} Work Screen Time because: {{reason}}",
        bodyFields: [AccountabilityWebhookBodyField] = [],
        snoozeNotifyThreshold: Int = AccountabilityTrigger.defaultSnoozeNotifyThreshold
    ) {
        self.isEnabled = isEnabled
        self.endpointURLString = endpointURLString
        self.bearerToken = bearerToken
        self.apiKey = apiKey
        self.headers = headers
        self.messageTemplate = messageTemplate
        self.bodyFields = bodyFields
        self.snoozeNotifyThreshold = snoozeNotifyThreshold
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case endpointURLString
        case bearerToken
        case apiKey
        case headers
        case messageTemplate
        case bodyFields
        case snoozeNotifyThreshold
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case bodyTemplate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let bodyFields = try container.decodeIfPresent([AccountabilityWebhookBodyField].self, forKey: .bodyFields)
            ?? Self.bodyFields(fromLegacyTemplate: legacyContainer.decodeIfPresent(String.self, forKey: .bodyTemplate))
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false,
            endpointURLString: try container.decodeIfPresent(String.self, forKey: .endpointURLString) ?? "",
            bearerToken: try container.decodeIfPresent(String.self, forKey: .bearerToken) ?? "",
            apiKey: try container.decodeIfPresent(String.self, forKey: .apiKey) ?? "",
            headers: try container.decodeIfPresent([AccountabilityWebhookHeader].self, forKey: .headers) ?? [],
            messageTemplate: try container.decodeIfPresent(String.self, forKey: .messageTemplate) ?? Self().messageTemplate,
            bodyFields: bodyFields,
            snoozeNotifyThreshold: try container.decodeIfPresent(Int.self, forKey: .snoozeNotifyThreshold)
                ?? AccountabilityTrigger.defaultSnoozeNotifyThreshold
        )
    }

    private static func bodyFields(fromLegacyTemplate template: String?) -> [AccountabilityWebhookBodyField] {
        guard let template,
              let data = template.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        return object.compactMap { key, value in
            guard key != "message", let stringValue = value as? String else { return nil }
            return AccountabilityWebhookBodyField(key: key, value: stringValue)
        }
    }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var schedules: [DaySchedule]
    public var warningLeadMinutes: Int
    public var snoozeMinutes: Int
    public var idleThresholdMinutes: Int
    public var quotes: [String]
    public var escalation: EscalationConfig
    public var accountabilityWebhook: AccountabilityWebhookConfig?

    public init(
        schedules: [DaySchedule],
        warningLeadMinutes: Int = 15,
        snoozeMinutes: Int = 15,
        idleThresholdMinutes: Int = 1,
        quotes: [String],
        escalation: EscalationConfig = EscalationConfig(),
        accountabilityWebhook: AccountabilityWebhookConfig? = nil
    ) {
        self.schedules = schedules
        self.warningLeadMinutes = warningLeadMinutes
        self.snoozeMinutes = snoozeMinutes
        self.idleThresholdMinutes = idleThresholdMinutes
        self.quotes = quotes
        self.escalation = escalation
        self.accountabilityWebhook = accountabilityWebhook
    }

    public static let defaultQuotes = [
        "You have done enough for today. Future you deserves rest.",
        "Stopping is part of the work. Let the day close.",
        "Your life is bigger than this session.",
        "Rest is not a reward for finishing everything.",
        "One more task can wait. Your evening should not."
    ]

    public static var `default`: AppConfig {
        AppConfig(schedules: Weekday.allCases.map { defaultSchedule(for: $0) }, quotes: defaultQuotes)
    }

    public static func defaultSchedule(for weekday: Weekday) -> DaySchedule {
        switch weekday {
        case .monday, .tuesday, .wednesday, .thursday, .friday:
            DaySchedule(
                weekday: weekday,
                isEnabled: true,
                start: TimeOfDay(hour: 18, minute: 0),
                end: TimeOfDay(hour: 6, minute: 0)
            )
        case .saturday, .sunday:
            DaySchedule(
                weekday: weekday,
                isEnabled: true,
                start: TimeOfDay(hour: 16, minute: 0),
                end: TimeOfDay(hour: 10, minute: 0)
            )
        }
    }

    public func schedule(for weekday: Weekday) -> DaySchedule? {
        schedules.first { $0.weekday == weekday }
    }
}

public struct DowntimeWindow: Codable, Equatable, Sendable {
    public var id: String
    public var weekday: Weekday
    public var start: Date
    public var end: Date

    public init(id: String, weekday: Weekday, start: Date, end: Date) {
        self.id = id
        self.weekday = weekday
        self.start = start
        self.end = end
    }
}

public enum HistoryEventType: String, Codable, Sendable {
    case promptShown
    case snoozed
    case dismissed
    case paused
    case resumed
}

public struct HistoryEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var type: HistoryEventType
    public var windowID: String?
    public var note: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        type: HistoryEventType,
        windowID: String?,
        note: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.windowID = windowID
        self.note = note
    }
}

public struct DailySummary: Codable, Equatable, Sendable {
    public var dateKey: String
    public var promptsShown: Int
    public var snoozes: Int
    public var dismissals: Int
    public var lastDismissedWindowID: String?
    public var lastDismissedAt: Date?
    public var dismissalReasons: [String]
    public var events: [HistoryEvent]

    public init(
        dateKey: String,
        promptsShown: Int = 0,
        snoozes: Int = 0,
        dismissals: Int = 0,
        lastDismissedWindowID: String? = nil,
        lastDismissedAt: Date? = nil,
        dismissalReasons: [String] = [],
        events: [HistoryEvent] = []
    ) {
        self.dateKey = dateKey
        self.promptsShown = promptsShown
        self.snoozes = snoozes
        self.dismissals = dismissals
        self.lastDismissedWindowID = lastDismissedWindowID
        self.lastDismissedAt = lastDismissedAt
        self.dismissalReasons = dismissalReasons
        self.events = events
    }
}

public struct History: Codable, Equatable, Sendable {
    public var dailySummaries: [String: DailySummary]

    public init(dailySummaries: [String: DailySummary] = [:]) {
        self.dailySummaries = dailySummaries
    }
}

public struct EscalationState: Equatable, Sendable {
    public var snoozeCount: Int
    public var title: String
    public var message: String
    public var confirmationPhrase: String
    public var requiresHold: Bool
    public var requiresPhrase: Bool
    public var requiresReason: Bool
}
