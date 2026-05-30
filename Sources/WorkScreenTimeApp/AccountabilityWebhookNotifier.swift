import Foundation
import WorkScreenTimeCore

enum AccountabilityWebhookEventKind: String, Codable, Sendable {
    case dismissed
    case snoozed
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
    case invalidBodyTemplate
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .disabledOrMissingURL:
            "Webhook is disabled or missing a URL."
        case .invalidURL:
            "Webhook URL is invalid."
        case .invalidBodyTemplate:
            "Webhook body template is not valid JSON."
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
                dismissalReason: "Test accountability webhook"
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
        for header in config.headers where header.isEnabled && !header.name.isEmpty {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        request.httpBody = try renderedBody(for: event, using: config)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AccountabilityWebhookError.serverError(httpResponse.statusCode)
        }
    }

    private func renderedBody(for event: AccountabilityWebhookEvent, using config: AccountabilityWebhookConfig) throws -> Data {
        let message = renderedMessage(from: config.messageTemplate, for: event)
        var object: [String: String] = ["message": message]
        let values = templateValues(for: event, message: message)
        for field in config.bodyFields where field.isEnabled && !field.key.isEmpty {
            object[field.key] = renderTemplate(field.value, values: values)
        }

        guard JSONSerialization.isValidJSONObject(object) else {
            throw AccountabilityWebhookError.invalidBodyTemplate
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func renderedMessage(from template: String, for event: AccountabilityWebhookEvent) -> String {
        let reason = event.dismissalReason ?? ""
        var rendered = renderTemplate(template, values: templateValues(for: event, message: reason))

        let appendsReason = event.kind == .dismissed || event.kind == .snoozed
        if appendsReason, !reason.isEmpty, !template.contains("{{reason}}") {
            rendered += "\nReason: \(reason)"
        }

        return rendered
    }

    private func templateValues(for event: AccountabilityWebhookEvent, message: String) -> [String: String] {
        [
            "app": "WorkScreenTimeApp",
            "event": event.kind.rawValue,
            "message": message,
            "timestamp": event.timestamp.ISO8601Format(),
            "dateKey": event.dateKey,
            "windowID": event.windowID ?? "",
            "snoozeCount": event.snoozeCount.map(String.init) ?? "",
            "reason": event.dismissalReason ?? "",
            "dismissalReason": event.dismissalReason ?? ""
        ]
    }

    private func renderTemplate(_ template: String, values: [String: String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{\s*([A-Za-z0-9_]+)\s*\}\}"#) else {
            return template
        }

        let nsRange = NSRange(template.startIndex..<template.endIndex, in: template)
        var rendered = template
        for match in regex.matches(in: template, range: nsRange).reversed() {
            guard let placeholderRange = Range(match.range(at: 1), in: template),
                  let fullRange = Range(match.range, in: template),
                  let value = values[String(template[placeholderRange])] else {
                continue
            }
            rendered.replaceSubrange(fullRange, with: value)
        }
        return rendered
    }
}
