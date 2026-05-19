import Foundation

public enum StoreError: Error {
    case couldNotCreateDirectory(URL)
}

public struct AppPaths: Sendable {
    public var applicationSupportDirectory: URL

    public init(applicationSupportDirectory: URL? = nil) {
        if let applicationSupportDirectory {
            self.applicationSupportDirectory = applicationSupportDirectory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.applicationSupportDirectory = base.appendingPathComponent("WorkScreenTimeApp", isDirectory: true)
        }
    }

    public var configURL: URL {
        applicationSupportDirectory.appendingPathComponent("config.json")
    }

    public var historyURL: URL {
        applicationSupportDirectory.appendingPathComponent("history.json")
    }

    public func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
    }
}

public final class ConfigStore {
    public let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL) {
        self.url = url
        self.encoder = JSONEncoder.workScreenTimeEncoder
        self.decoder = JSONDecoder.workScreenTimeDecoder
    }

    public func load() -> AppConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? decoder.decode(AppConfig.self, from: data) else {
            let config = AppConfig.default
            try? save(config)
            return config
        }

        return normalized(config)
    }

    public func save(_ config: AppConfig) throws {
        try url.ensureParentDirectoryExists()
        let data = try encoder.encode(normalized(config))
        try data.write(to: url, options: [.atomic])
    }

    private func normalized(_ config: AppConfig) -> AppConfig {
        var copy = config
        var existing: [Weekday: DaySchedule] = [:]
        for schedule in copy.schedules {
            existing[schedule.weekday] = schedule
        }

        copy.schedules = Weekday.allCases.map { weekday in
            existing[weekday] ?? AppConfig.defaultSchedule(for: weekday)
        }
        copy.warningLeadMinutes = max(0, copy.warningLeadMinutes)
        copy.snoozeMinutes = max(1, copy.snoozeMinutes)
        copy.idleThresholdMinutes = max(1, copy.idleThresholdMinutes)
        copy.quotes = copy.quotes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if copy.quotes.isEmpty {
            copy.quotes = AppConfig.defaultQuotes
        }
        copy.escalation = normalized(copy.escalation)
        copy.accountabilityWebhook = normalized(copy.accountabilityWebhook)
        return copy
    }

    private func normalized(_ escalation: EscalationConfig) -> EscalationConfig {
        var copy = escalation
        copy.holdRequiredAtSnoozeCount = max(0, copy.holdRequiredAtSnoozeCount)
        copy.phraseRequiredAtSnoozeCount = max(0, copy.phraseRequiredAtSnoozeCount)
        copy.reasonRequiredAtSnoozeCount = max(0, copy.reasonRequiredAtSnoozeCount)

        let confirmationPhrase = copy.confirmationPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if confirmationPhrase.isEmpty {
            copy.confirmationPhrase = EscalationConfig().confirmationPhrase
        } else {
            copy.confirmationPhrase = confirmationPhrase
        }

        return copy
    }

    private func normalized(_ webhook: AccountabilityWebhookConfig?) -> AccountabilityWebhookConfig? {
        guard var copy = webhook else { return nil }
        copy.endpointURLString = copy.endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.bearerToken = copy.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.apiKey = copy.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.headers = copy.headers.compactMap { header in
            var header = header
            header.name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            header.value = header.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return header.name.isEmpty && header.value.isEmpty ? nil : header
        }
        copy.bodyFields = copy.bodyFields.compactMap { field in
            var field = field
            field.key = field.key.trimmingCharacters(in: .whitespacesAndNewlines)
            field.value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return field.key.isEmpty && field.value.isEmpty ? nil : field
        }
        copy.messageTemplate = copy.messageTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.messageTemplate.isEmpty {
            copy.messageTemplate = AccountabilityWebhookConfig().messageTemplate
        }
        if copy.endpointURLString.isEmpty {
            copy.isEnabled = false
        }
        return copy
    }
}

public final class HistoryStore {
    public let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL) {
        self.url = url
        self.encoder = JSONEncoder.workScreenTimeEncoder
        self.decoder = JSONDecoder.workScreenTimeDecoder
    }

    public func load() -> History {
        guard let data = try? Data(contentsOf: url),
              let history = try? decoder.decode(History.self, from: data) else {
            let history = History()
            try? save(history)
            return history
        }

        return history
    }

    public func save(_ history: History) throws {
        try url.ensureParentDirectoryExists()
        let data = try encoder.encode(history)
        try data.write(to: url, options: [.atomic])
    }

    public func summary(for dateKey: String) -> DailySummary {
        load().dailySummaries[dateKey] ?? DailySummary(dateKey: dateKey)
    }

    public func recordPrompt(dateKey: String, windowID: String, at date: Date) throws {
        try mutateSummary(dateKey: dateKey) { summary in
            summary.promptsShown += 1
            summary.events.append(HistoryEvent(timestamp: date, type: .promptShown, windowID: windowID))
        }
    }

    public func recordSnooze(dateKey: String, windowID: String, until: Date, at date: Date) throws {
        try mutateSummary(dateKey: dateKey) { summary in
            summary.snoozes += 1
            summary.events.append(HistoryEvent(timestamp: date, type: .snoozed, windowID: windowID, note: until.ISO8601Format()))
        }
    }

    public func recordDismissal(dateKey: String, windowID: String, reason: String?, at date: Date) throws {
        try mutateSummary(dateKey: dateKey) { summary in
            let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = reason.flatMap { $0.isEmpty ? nil : $0 }
            summary.dismissals += 1
            summary.lastDismissedWindowID = windowID
            summary.lastDismissedAt = date
            if let note {
                summary.dismissalReasons.append(note)
            }
            summary.events.append(HistoryEvent(timestamp: date, type: .dismissed, windowID: windowID, note: note))
        }
    }

    public func recordPause(dateKey: String, until: Date?, at date: Date) throws {
        try mutateSummary(dateKey: dateKey) { summary in
            summary.events.append(HistoryEvent(timestamp: date, type: .paused, windowID: nil, note: until?.ISO8601Format()))
        }
    }

    public func recordResume(dateKey: String, at date: Date) throws {
        try mutateSummary(dateKey: dateKey) { summary in
            summary.events.append(HistoryEvent(timestamp: date, type: .resumed, windowID: nil))
        }
    }

    public func clearDismissal(dateKey: String, windowID: String, at date: Date) throws {
        try mutateSummary(dateKey: dateKey) { summary in
            if summary.lastDismissedWindowID == windowID {
                summary.lastDismissedWindowID = nil
                summary.lastDismissedAt = nil
            }
            summary.events.append(HistoryEvent(timestamp: date, type: .resumed, windowID: windowID))
        }
    }

    public func clear(dateKey: String) throws {
        var history = load()
        history.dailySummaries.removeValue(forKey: dateKey)
        try save(history)
    }

    public func clear() throws {
        try save(History())
    }

    private func mutateSummary(dateKey: String, mutate: (inout DailySummary) -> Void) throws {
        var history = load()
        var summary = history.dailySummaries[dateKey] ?? DailySummary(dateKey: dateKey)
        mutate(&summary)
        history.dailySummaries[dateKey] = summary
        try save(history)
    }
}

private extension JSONEncoder {
    static var workScreenTimeEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var workScreenTimeDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension URL {
    func ensureParentDirectoryExists() throws {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
    }
}
