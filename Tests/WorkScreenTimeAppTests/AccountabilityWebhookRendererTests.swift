import Foundation
import Testing
import WorkScreenTimeCore
@testable import WorkScreenTimeApp

struct AccountabilityWebhookRendererTests {
    private let notifier = AccountabilityWebhookNotifier()
    // 21:30 local time, so the formatted "prompts again" time is predictable.
    private let snoozeUntil = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 21, minute: 30))!

    private func event(
        _ kind: AccountabilityWebhookEventKind,
        reason: String? = "one last fix",
        snoozeMinutes: Int? = nil,
        snoozeUntil: Date? = nil
    ) -> AccountabilityWebhookEvent {
        AccountabilityWebhookEvent(
            kind: kind,
            timestamp: Date(timeIntervalSince1970: 0),
            dateKey: "2026-11-03",
            windowID: "w1",
            snoozeCount: 3,
            dismissalReason: reason,
            snoozeMinutes: snoozeMinutes,
            snoozeUntil: snoozeUntil
        )
    }

    private func message(_ event: AccountabilityWebhookEvent, template: String = AccountabilityWebhookConfig().messageTemplate) -> String {
        notifier.renderedMessage(from: template, for: event)
    }

    private var expectedTime: String { snoozeUntil.formatted(date: .omitted, time: .shortened) }

    @Test func dismissedUsesDefaultTemplate() {
        #expect(message(event(.dismissed)) == "I dismissed Work Screen Time for the day because: one last fix")
    }

    @Test func snoozedShowsDurationAndReturnTime() {
        let snoozed = event(.snoozed, snoozeMinutes: 15, snoozeUntil: snoozeUntil)
        #expect(message(snoozed) == "I snoozed Work Screen Time for 15 min because: one last fix\nPrompts again at \(expectedTime)")
    }

    @Test func missingReasonUsesPlaceholder() {
        #expect(message(event(.dismissed, reason: "  ")) == "I dismissed Work Screen Time for the day because: <No Reason Given>")
    }

    @Test func testEventCollapsesEmptyDuration() {
        #expect(message(event(.test, reason: "hi")) == "I test Work Screen Time because: hi")
    }

    @Test func legacyTemplateGetsReasonAndSnoozeLineAppended() {
        let snoozed = event(.snoozed, snoozeMinutes: 15, snoozeUntil: snoozeUntil)
        #expect(message(snoozed, template: "Snooze alert") == "Snooze alert\nReason: one last fix\nPrompts again at \(expectedTime)")
    }

    @Test func legacyTemplateDismissalGetsOnlyReason() {
        #expect(message(event(.dismissed), template: "Dismissed") == "Dismissed\nReason: one last fix")
    }

    @Test func templateUsingSnoozeDetailIsNotAppendedTwice() {
        let snoozed = event(.snoozed, snoozeMinutes: 15, snoozeUntil: snoozeUntil)
        #expect(message(snoozed, template: "{{reason}} | {{snoozeDetail}}") == "one last fix | Prompts again at \(expectedTime)")
    }

    @Test func unknownPlaceholdersAreLeftAsIs() {
        #expect(message(event(.dismissed), template: "{{nope}} {{ event }}") == "{{nope}} dismissed\nReason: one last fix")
    }

    @Test func bodyFieldsRenderPlaceholdersAndSkipDisabledOnes() throws {
        let config = AccountabilityWebhookConfig(
            bodyFields: [
                .init(key: "groupId", value: "abc@g.us"),
                .init(key: "kind", value: "{{event}}:{{snoozeMinutes}}"),
                .init(isEnabled: false, key: "skipped", value: "x")
            ]
        )
        let data = try notifier.renderedBody(for: event(.snoozed, snoozeMinutes: 15, snoozeUntil: snoozeUntil), using: config)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])

        #expect(object["groupId"] == "abc@g.us")
        #expect(object["kind"] == "snoozed:15")
        #expect(object["skipped"] == nil)
        #expect(object["message"]?.hasPrefix("I snoozed Work Screen Time for 15 min") == true)
    }
}
