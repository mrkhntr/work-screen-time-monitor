import Foundation
import WorkScreenTimeCore

enum AccountabilityWebhookEventKind: String, Codable, Sendable {
    case dismissed
    case test
}

struct AccountabilityWebhookEvent: Sendable {
    var kind: AccountabilityWebhookEventKind
    var timestamp: Date
    var dateKey: String
    var windowID: String?
    var snoozeCount: Int?
    var dismissalReason: String?
}

enum AccountabilityWebhookError: LocalizedError {
    case disabledOrMissingURL
    case invalidURL
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .disabledOrMissingURL:
            "Webhook is disabled or missing a URL."
        case .invalidURL:
            "Webhook URL is invalid."
        case .serverError(let statusCode):
            "Webhook returned HTTP \(statusCode)."
        }
    }
}

struct AccountabilityWebhookNotifier {
    func send(_ event: AccountabilityWebhookEvent, using config: AccountabilityWebhookConfig?) async throws {
        guard let config,
              config.isEnabled,
              !config.endpointURLString.isEmpty else {
            throw AccountabilityWebhookError.disabledOrMissingURL
        }
        try await deliver(event, using: config)
    }

    func sendTest(using config: AccountabilityWebhookConfig?) async throws {
        guard var config,
              !config.endpointURLString.isEmpty else {
            throw AccountabilityWebhookError.disabledOrMissingURL
        }
        config.isEnabled = true
        try await deliver(
            AccountabilityWebhookEvent(
                kind: .test,
                timestamp: Date(),
                dateKey: "test",
                windowID: nil,
                snoozeCount: nil,
                dismissalReason: nil
            ),
            using: config
        )
    }

    private func deliver(_ event: AccountabilityWebhookEvent, using config: AccountabilityWebhookConfig) async throws {
        guard let url = URL(string: config.endpointURLString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw AccountabilityWebhookError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !config.bearerToken.isEmpty {
            request.setValue("Bearer \(config.bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if !config.apiKey.isEmpty {
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        }

        request.httpBody = try JSONEncoder().encode(payload(for: event, message: config.messageTemplate))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AccountabilityWebhookError.serverError(httpResponse.statusCode)
        }
    }

    private func payload(for event: AccountabilityWebhookEvent, message: String) -> AccountabilityWebhookPayload {
        AccountabilityWebhookPayload(
            event: event.kind,
            app: "WorkScreenTimeApp",
            message: renderedMessage(from: message, for: event),
            timestamp: event.timestamp.ISO8601Format(),
            dateKey: event.dateKey,
            windowID: event.windowID,
            snoozeCount: event.snoozeCount,
            dismissalReason: event.dismissalReason
        )
    }

    private func renderedMessage(from template: String, for event: AccountabilityWebhookEvent) -> String {
        let reason = event.dismissalReason ?? ""
        var rendered = template
            .replacingOccurrences(of: "{{event}}", with: event.kind.rawValue)
            .replacingOccurrences(of: "{{timestamp}}", with: event.timestamp.ISO8601Format())
            .replacingOccurrences(of: "{{dateKey}}", with: event.dateKey)
            .replacingOccurrences(of: "{{windowID}}", with: event.windowID ?? "")
            .replacingOccurrences(of: "{{snoozeCount}}", with: event.snoozeCount.map(String.init) ?? "")
            .replacingOccurrences(of: "{{reason}}", with: reason)

        if event.kind == .dismissed, !reason.isEmpty, !template.contains("{{reason}}") {
            rendered += "\nReason: \(reason)"
        }

        return rendered
    }
}

private struct AccountabilityWebhookPayload: Encodable {
    var event: AccountabilityWebhookEventKind
    var app: String
    var message: String
    var timestamp: String
    var dateKey: String
    var windowID: String?
    var snoozeCount: Int?
    var dismissalReason: String?
}
