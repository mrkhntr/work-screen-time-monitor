import Foundation
import SwiftUI
import WorkScreenTimeCore

/// The downtime checkpoint: an optional pause point up top, then whatever the escalation level requires before snoozing or dismissing.
struct FullScreenPromptView: View {
    private static let minimumReasonLength = 12

    let config: AppConfig
    let escalation: EscalationState
    let photos: [URL]
    let onSnooze: (_ minutes: Int, _ reason: String?) -> Void
    let onDismiss: (String?) -> Void
    @ObservedObject var formState: PromptFormState

    private var pauseKind: PausePointKind? { escalation.requiresPause ? formState.pauseKind : nil }
    private var palette: PromptPalette { PromptPalette(kind: pauseKind) }
    private func pauseRemaining(at elapsed: Double) -> Double {
        escalation.requiresPause ? max(0, Double(escalation.pauseSeconds) - elapsed) : 0
    }

    private var reasonText: String { formState.reason.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var phraseDone: Bool {
        !escalation.requiresPhrase || ConfirmationPhraseMatcher.matches(formState.phrase, phrase: escalation.confirmationPhrase)
    }
    private var reasonDone: Bool { !escalation.requiresReason || reasonText.count >= Self.minimumReasonLength }
    private var canAct: Bool { phraseDone && reasonDone }

    private var photo: URL? { photos.isEmpty ? nil : photos[formState.pauseSeed % photos.count] }

    private var quote: String {
        let quotes = config.quotes.isEmpty ? AppConfig.defaultQuotes : config.quotes
        return quotes[formState.pauseSeed % quotes.count]
    }

    private var title: String {
        switch pauseKind {
        case .breathe: "Why are you here?"
        case .remind: "Remember what tonight is for"
        case nil: escalation.title
        }
    }

    private var subtitle: String {
        guard pauseKind != nil else { return escalation.message }
        let count = escalation.snoozeCount
        return "You've snoozed \(count == 1 ? "once" : "\(count) times") tonight."
    }

    private var notifyWarning: String? {
        guard let webhook = config.accountabilityWebhook, webhook.isEnabled else { return nil }
        switch formState.action {
        case .dismiss:
            return "Dismissing will notify your accountability contact."
        case .snooze, .quickSnooze:
            let notifies = AccountabilityTrigger.notifiesOnSnooze(
                totalSnoozesAfter: escalation.snoozeCount + 1,
                threshold: webhook.snoozeNotifyThreshold
            )
            return notifies ? "Snoozing again will notify your accountability contact." : nil
        }
    }

    private var reasonUsage: String {
        config.accountabilityWebhook?.isEnabled == true
            ? "We\u{2019}ll remind you of this halfway through your snooze, and share it with your accountability contact."
            : "We\u{2019}ll remind you of this halfway through your snooze."
    }

    private var reasonLabel: String {
        escalation.requiresReason
            ? "What are you working on, and why tonight? (\(Self.minimumReasonLength)+ characters)"
            : "Reason (optional)"
    }

    private var holdHint: String? {
        escalation.requiresHold && canAct ? "Press and hold to confirm." : nil
    }

    var body: some View {
        // Ticks only while a pause point is showing; otherwise nothing on screen depends on time.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !escalation.requiresPause)) { context in
            content(elapsed: max(0, context.date.timeIntervalSince(formState.shownAt)))
        }
    }

    private func content(elapsed: Double) -> some View {
        let pauseRemaining = pauseRemaining(at: elapsed)
        let hint = pauseRemaining > 0 ? nil : holdHint
        return ZStack {
            palette.background.ignoresSafeArea()

            VStack(spacing: 28) {
                if let pauseKind {
                    ModeChip(kind: pauseKind, palette: palette)
                }

                VStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.ink)
                    Text(subtitle)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.ink.opacity(0.65))
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 680)

                hero(elapsed: elapsed)

                // Nothing to justify until the pause is over.
                if pauseRemaining == 0 {
                    checkpoint
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                VStack(spacing: 14) {
                    if pauseRemaining > 0 {
                        CountdownRing(total: Double(escalation.pauseSeconds), remaining: pauseRemaining, palette: palette)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        actions
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }

                    if let hint {
                        Text(hint)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(palette.ink.opacity(0.6))
                    } else if pauseRemaining == 0, let notifyWarning {
                        Text(notifyWarning)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.yellow)
                    }
                }
                .frame(minHeight: 90, alignment: .top)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: pauseRemaining == 0)
            }
            .padding(48)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: pauseRemaining == 0)
        }
    }

    @ViewBuilder
    private func hero(elapsed: Double) -> some View {
        switch pauseKind {
        case .breathe:
            BreathingShape(time: elapsed, palette: palette)
        case .remind:
            VStack(spacing: 18) {
                PromptPhoto(url: photo, seed: formState.pauseSeed, palette: palette)
                Text("\u{201C}\(quote)\u{201D}")
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.ink.opacity(0.85))
                    .frame(maxWidth: 560)
            }
        case nil:
            PromptPhoto(url: photo, seed: formState.pauseSeed, palette: palette)
        }
    }

    /// The reflection that earns more time: what's required to snooze or dismiss at this escalation level.
    private var checkpoint: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(escalation.requiresReason ? "Reflect before you keep working" : "Add a note")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.ink)
                Text(reasonUsage)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.ink.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 6)
            .frame(width: 460, alignment: .leading)

            if escalation.requiresPhrase {
                PillField(
                    label: "Type \u{201C}\(escalation.confirmationPhrase)\u{201D}",
                    placeholder: escalation.confirmationPhrase,
                    text: $formState.phrase,
                    isDone: phraseDone,
                    isMissing: formState.showMissing && !phraseDone,
                    palette: palette
                )
            }
            PillField(
                label: reasonLabel,
                placeholder: "e.g. Fixing checkout before tomorrow\u{2019}s launch",
                text: $formState.reason,
                isDone: reasonDone && !reasonText.isEmpty,
                isMissing: formState.showMissing && !reasonDone,
                palette: palette
            )
        }
        .padding(20)
        .background(palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func title(for action: PromptAction) -> String {
        switch action {
        case .snooze: "Snooze \(config.snoozeMinutes) min"
        case .quickSnooze: "Snooze 1 min"
        case .dismiss: "Dismiss for today"
        }
    }

    private func perform(_ action: PromptAction) {
        let reason = reasonText.isEmpty ? nil : reasonText
        switch action {
        case .snooze: onSnooze(config.snoozeMinutes, reason)
        case .quickSnooze: onSnooze(1, reason)
        case .dismiss: onDismiss(reason)
        }
    }

    /// Snooze by default; the menu swaps the main button to the other action.
    private var actions: some View {
        HStack(spacing: 10) {
            ActionPill(
                title: title(for: formState.action),
                requiresHold: escalation.requiresHold,
                isEnabled: canAct,
                isDefault: true,
                palette: palette,
                action: { perform(formState.action) },
                onBlockedTap: { formState.flagMissing() }
            )
            .id(formState.action)

            Menu {
                Picker("Action", selection: $formState.action) {
                    ForEach(PromptAction.allCases, id: \.self) { Text(title(for: $0)).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(14)
            .background(palette.ink.opacity(0.1), in: Circle())
            .help("More actions")
        }
    }
}
