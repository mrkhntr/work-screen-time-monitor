import Foundation
import SwiftUI
import WorkScreenTimeCore

struct FullScreenPromptView: View {
    private let minimumReasonLength = 12

    let config: AppConfig
    let escalation: EscalationState
    let onSnooze: (String?) -> Void
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

    private var webhookEnabled: Bool { config.accountabilityWebhook?.isEnabled == true }

    private var willNotify: Bool {
        guard webhookEnabled else { return false }
        switch formState.selectedAction {
        case .dismiss:
            return true
        case .snooze:
            let threshold = config.accountabilityWebhook?.snoozeNotifyThreshold
                ?? AccountabilityTrigger.defaultSnoozeNotifyThreshold
            return AccountabilityTrigger.notifiesOnSnooze(totalSnoozesAfter: escalation.snoozeCount + 1, threshold: threshold)
        }
    }

    private var notifyWarning: String {
        formState.selectedAction == .dismiss
            ? "Dismissing will notify your accountability contact."
            : "Snoozing again will notify your accountability contact."
    }

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

                if willNotify {
                    Text(notifyWarning)
                        .font(.callout.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.yellow)
                        .frame(maxWidth: 620)
                }

                Color.clear
                    .frame(width: BouncingActionCluster.clusterSize.width, height: BouncingActionCluster.clusterSize.height)
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

            BouncingActionCluster(
                config: config,
                formState: formState,
                onPrimaryAction: performSelectedAction
            )
        }
    }

    private func performSelectedAction() {
        formState.attemptedAction = true
        guard canDismiss else { return }
        switch formState.selectedAction {
        case .snooze: onSnooze(reasonText.isEmpty ? nil : reasonText)
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

private struct BouncingActionCluster: View {
    static let clusterSize = CGSize(width: 260, height: 48)

    private let margin: CGFloat = 32
    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    let config: AppConfig
    @ObservedObject var formState: PromptFormState
    let onPrimaryAction: () -> Void

    @State private var position = CGPoint.zero
    @State private var velocity = CGVector(dx: 38, dy: -31)
    @State private var lastTick: Date?
    @State private var isSwitchOpen = false
    @State private var hasInitializedPosition = false

    var body: some View {
        GeometryReader { proxy in
            PromptActionCluster(
                config: config,
                formState: formState,
                isSwitchOpen: $isSwitchOpen,
                onPrimaryAction: onPrimaryAction
            )
            .frame(width: Self.clusterSize.width, height: Self.clusterSize.height)
            .position(displayPosition(in: proxy.size))
            .onAppear {
                initializePositionIfNeeded(in: proxy.size)
            }
            .onChange(of: proxy.size) { newSize in
                constrainPosition(to: newSize)
            }
            .onReceive(timer) { now in
                updatePosition(now: now, in: proxy.size)
            }
        }
        .ignoresSafeArea()
    }

    private func displayPosition(in size: CGSize) -> CGPoint { currentPosition(in: size) }

    private func currentPosition(in size: CGSize) -> CGPoint {
        hasInitializedPosition ? position : initialPosition(in: size)
    }

    private func initializePositionIfNeeded(in size: CGSize) {
        guard !hasInitializedPosition else { return }
        position = initialPosition(in: size)
        hasInitializedPosition = true
        lastTick = Date()
    }

    private func initialPosition(in size: CGSize) -> CGPoint {
        let bounds = movementBounds(in: size)
        return CGPoint(
            x: clamp(size.width / 2, min: bounds.minX, max: bounds.maxX),
            y: clamp(size.height * 0.72, min: bounds.minY, max: bounds.maxY)
        )
    }

    private func updatePosition(now: Date, in size: CGSize) {
        initializePositionIfNeeded(in: size)

        guard !isSwitchOpen else {
            lastTick = now
            return
        }

        let elapsed = min(now.timeIntervalSince(lastTick ?? now), 0.1)
        lastTick = now

        var nextPosition = position
        var nextVelocity = velocity
        let bounds = movementBounds(in: size)

        nextPosition.x += nextVelocity.dx * elapsed
        nextPosition.y += nextVelocity.dy * elapsed

        if nextPosition.x <= bounds.minX {
            nextPosition.x = bounds.minX
            nextVelocity.dx = abs(nextVelocity.dx)
        } else if nextPosition.x >= bounds.maxX {
            nextPosition.x = bounds.maxX
            nextVelocity.dx = -abs(nextVelocity.dx)
        }

        if nextPosition.y <= bounds.minY {
            nextPosition.y = bounds.minY
            nextVelocity.dy = abs(nextVelocity.dy)
        } else if nextPosition.y >= bounds.maxY {
            nextPosition.y = bounds.maxY
            nextVelocity.dy = -abs(nextVelocity.dy)
        }

        position = nextPosition
        velocity = nextVelocity
    }

    private func constrainPosition(to size: CGSize) {
        guard hasInitializedPosition else { return }

        let bounds = movementBounds(in: size)
        position = CGPoint(
            x: clamp(position.x, min: bounds.minX, max: bounds.maxX),
            y: clamp(position.y, min: bounds.minY, max: bounds.maxY)
        )
    }

    private func movementBounds(in size: CGSize) -> CGRect {
        let halfWidth = Self.clusterSize.width / 2
        let halfHeight = Self.clusterSize.height / 2
        let minX = halfWidth + margin
        let maxX = max(minX, size.width - halfWidth - margin)
        let minY = halfHeight + margin
        let maxY = max(minY, size.height - halfHeight - margin)

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }
}

private struct PromptActionCluster: View {
    let config: AppConfig
    @ObservedObject var formState: PromptFormState
    @Binding var isSwitchOpen: Bool
    let onPrimaryAction: () -> Void

    var body: some View {
        ZStack {
            Button(formState.selectedAction.title(snoozeMinutes: config.snoozeMinutes)) {
                onPrimaryAction()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .font(.system(size: 20, weight: .semibold))
            .frame(minWidth: 180)

            HStack {
                Spacer()
                    .frame(width: 206)
                Button {
                    isSwitchOpen.toggle()
                } label: {
                    Text("Switch")
                        .frame(width: 54, height: 18)
                }
                .buttonStyle(.borderless)
                .controlSize(.large)
                .popover(isPresented: $isSwitchOpen, arrowEdge: .bottom) {
                    Button(formState.selectedAction.alternate.title(snoozeMinutes: config.snoozeMinutes)) {
                        formState.selectedAction = formState.selectedAction.alternate
                        formState.attemptedAction = false
                        isSwitchOpen = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(12)
                }
            }
        }
        .frame(width: BouncingActionCluster.clusterSize.width, height: BouncingActionCluster.clusterSize.height)
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
