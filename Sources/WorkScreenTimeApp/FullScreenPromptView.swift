import Foundation
import SwiftUI
import WorkScreenTimeCore

struct FullScreenPromptView: View {
    private let minimumReasonLength = 12

    let config: AppConfig
    let escalation: EscalationState
    let onSnooze: () -> Void
    let onDismiss: (String?) -> Void
    @ObservedObject var formState: PromptFormState

    private var reasonText: String {
        formState.reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var requirements: [Requirement] {
        [
            escalation.requiresHold ? Requirement(
                id: "hold", label: "Hold for 2 seconds",
                message: "Hold the unlock control for 2 seconds.",
                isComplete: formState.holdUnlocked
            ) : nil,
            escalation.requiresPhrase ? Requirement(
                id: "phrase", label: "Type the phrase exactly",
                message: "Type the confirmation phrase exactly.",
                isComplete: ConfirmationPhraseMatcher.matches(formState.phrase, phrase: escalation.confirmationPhrase)
            ) : nil,
            escalation.requiresReason ? Requirement(
                id: "reason", label: "Write a real reason",
                message: "Write a reason with at least \(minimumReasonLength) characters.",
                isComplete: reasonText.count >= minimumReasonLength
            ) : nil,
        ].compactMap { $0 }
    }

    private var canDismiss: Bool { requirements.allSatisfy(\.isComplete) }
    private var validationMessages: [String] { requirements.filter { !$0.isComplete }.map(\.message) }

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.085)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Text(escalation.title)
                    .font(.system(size: 40, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Text(escalation.message)
                    .font(.system(size: 21, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: 760)

                AsyncImage(url: URL(string: "https://gifroz.vercel.app/")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.white.opacity(0.05)
                }
                .frame(width: 240, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if !requirements.isEmpty {
                    RequirementChecklist(requirements: requirements)
                }

                if escalation.requiresHold {
                    HoldToUnlockButton(isUnlocked: $formState.holdUnlocked)
                }

                if escalation.requiresPhrase {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Type: \(escalation.confirmationPhrase)")
                            .foregroundStyle(.white.opacity(0.72))
                        TextField(escalation.confirmationPhrase, text: $formState.phrase)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: formState.phrase) { _ in
                                formState.attemptedAction = false
                            }
                    }
                    .frame(width: 420)
                }

                if escalation.requiresReason {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Why are you continuing past this boundary?")
                            .foregroundStyle(.white.opacity(0.72))
                        TextField("One real sentence, at least \(minimumReasonLength) characters", text: $formState.reason)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: formState.reason) { _ in
                                formState.attemptedAction = false
                            }
                    }
                    .frame(width: 420)
                }

                ZStack {
                    Button(formState.selectedAction.title(snoozeMinutes: config.snoozeMinutes)) {
                        performSelectedAction()
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(minWidth: 180)

                    HStack {
                        Spacer()
                            .frame(width: 206)
                        Menu {
                            Button(formState.selectedAction.alternate.title(snoozeMinutes: config.snoozeMinutes)) {
                                formState.selectedAction = formState.selectedAction.alternate
                                formState.attemptedAction = false
                            }
                        } label: {
                            Text("Switch")
                                .frame(width: 54, height: 18)
                        }
                        .menuStyle(.borderlessButton)
                        .controlSize(.large)
                    }
                }
                .frame(width: 260)
                .padding(.top, 4)

                if !validationMessages.isEmpty && (formState.attemptedAction || escalation.requiresHold) {
                    VStack(spacing: 4) {
                        ForEach(validationMessages, id: \.self) { message in
                            Text(message)
                        }
                    }
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(formState.attemptedAction ? Color.orange : Color.white.opacity(0.7))
                }
            }
            .padding(40)
            .frame(maxWidth: 920)
        }
    }

    private func performSelectedAction() {
        formState.attemptedAction = true
        guard canDismiss else { return }
        switch formState.selectedAction {
        case .snooze: onSnooze()
        case .dismiss: onDismiss(reasonText.isEmpty ? nil : reasonText)
        }
    }
}

private struct Requirement: Identifiable {
    let id: String
    let label: String
    let message: String
    let isComplete: Bool
}

private struct RequirementChecklist: View {
    let requirements: [Requirement]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Required before snoozing or dismissing")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))

            ForEach(requirements) { req in
                HStack(spacing: 8) {
                    Image(systemName: req.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(req.isComplete ? Color.green : Color.white.opacity(0.45))
                    Text(req.label)
                        .foregroundStyle(req.isComplete ? Color.white.opacity(0.82) : Color.white.opacity(0.64))
                }
                .font(.callout)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct HoldToUnlockButton: View {
    private let holdDuration: TimeInterval = 2

    @Binding var isUnlocked: Bool
    @State private var isHolding = false
    @State private var holdStartedAt: Date?
    @State private var secondsRemaining: TimeInterval = 2

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 220)
                .opacity(isUnlocked ? 0 : 1)
        }
            .foregroundStyle(isUnlocked ? Color.white : Color.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(isUnlocked ? 0.25 : 0), lineWidth: 1)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        beginHolding()
                    }
                    .onEnded { _ in
                        cancelHoldingIfNeeded()
                    }
            )
            .onReceive(timer) { now in
                updateCountdown(now: now)
            }
            .accessibilityLabel(isUnlocked ? "Dismiss unlocked" : "Hold to unlock dismiss")
    }

    private var title: String {
        if isUnlocked {
            "Actions unlocked"
        } else if isHolding {
            "Keep holding... \(String(format: "%.1f", secondsRemaining))s"
        } else {
            "Hold to unlock actions"
        }
    }

    private var progress: Double {
        isUnlocked ? 1 : 1 - (secondsRemaining / holdDuration)
    }

    private var background: some View {
        Group {
            if isUnlocked {
                Color.green.opacity(0.55)
            } else if isHolding {
                Color.orange.opacity(0.9)
            } else {
                Color(nsColor: .controlBackgroundColor)
            }
        }
    }

    private func beginHolding() {
        guard !isUnlocked else {
            return
        }

        if !isHolding {
            isHolding = true
            holdStartedAt = Date()
            secondsRemaining = holdDuration
        }
    }

    private func cancelHoldingIfNeeded() {
        guard !isUnlocked else {
            return
        }

        isHolding = false
        holdStartedAt = nil
        secondsRemaining = holdDuration
    }

    private func updateCountdown(now: Date) {
        guard isHolding, let holdStartedAt, !isUnlocked else {
            return
        }

        let elapsed = now.timeIntervalSince(holdStartedAt)
        secondsRemaining = max(0, holdDuration - elapsed)

        if elapsed >= holdDuration {
            isUnlocked = true
            isHolding = false
            self.holdStartedAt = nil
            secondsRemaining = 0
        }
    }
}
