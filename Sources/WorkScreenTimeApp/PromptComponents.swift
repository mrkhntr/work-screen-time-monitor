import SwiftUI

/// Dark tonal palettes with pastel accents (Material-style), one per pause mode plus a neutral one.
struct PromptPalette {
    let background: Color
    let accent: Color
    let onAccent: Color
    let ink = Color(white: 0.96)

    init(kind: PausePointKind?) {
        switch kind {
        case .breathe:
            background = Color(red: 0.11, green: 0.10, blue: 0.19)
            accent = Color(red: 0.80, green: 0.74, blue: 1.00)
            onAccent = Color(red: 0.17, green: 0.12, blue: 0.36)
        case .remind:
            background = Color(red: 0.17, green: 0.11, blue: 0.09)
            accent = Color(red: 1.00, green: 0.72, blue: 0.60)
            onAccent = Color(red: 0.33, green: 0.13, blue: 0.05)
        case nil:
            background = Color(red: 0.09, green: 0.10, blue: 0.12)
            accent = Color(red: 0.66, green: 0.78, blue: 1.00)
            onAccent = Color(red: 0.04, green: 0.13, blue: 0.30)
        }
    }
}

struct ModeChip: View {
    let kind: PausePointKind
    let palette: PromptPalette

    private var label: (title: String, symbol: String) {
        switch kind {
        case .breathe: ("Breathe", "wind")
        case .remind: ("Remind", "photo.on.rectangle.angled")
        }
    }

    var body: some View {
        Label(label.title, systemImage: label.symbol)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(palette.accent, in: Capsule())
    }
}

/// A scalloped shape that grows over a 4s inhale and shrinks over a 6s exhale.
struct BreathingShape: View {
    private static let inhaleSeconds: Double = 4
    private static let exhaleSeconds: Double = 6

    let time: Double
    let palette: PromptPalette

    private var phase: (isInhale: Bool, progress: Double) {
        let t = time.truncatingRemainder(dividingBy: Self.inhaleSeconds + Self.exhaleSeconds)
        return t < Self.inhaleSeconds
            ? (true, t / Self.inhaleSeconds)
            : (false, (t - Self.inhaleSeconds) / Self.exhaleSeconds)
    }

    private var scale: Double {
        let eased = 0.5 - 0.5 * cos(phase.progress * .pi)
        return phase.isInhale ? 0.55 + 0.45 * eased : 1 - 0.45 * eased
    }

    var body: some View {
        ZStack {
            Image(systemName: "seal.fill")
                .resizable()
                .foregroundStyle(palette.accent.opacity(0.22))
                .rotationEffect(.degrees(-time * 6))
            Image(systemName: "seal.fill")
                .resizable()
                .foregroundStyle(palette.accent)
                .scaleEffect(scale * 0.92)
                .rotationEffect(.degrees(time * 10))
            Text(phase.isInhale ? "Breathe in" : "Breathe out")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.onAccent)
        }
        .frame(width: 260, height: 260)
    }
}

/// One of the user's photos, or a seeded random one from picsum when they haven't added any.
struct PromptPhoto: View {
    let url: URL?
    let seed: Int
    let palette: PromptPalette

    @State private var tilt: Double = 0

    // The picsum fallback is seeded so every display shows the same photo.
    private var source: URL? { url ?? URL(string: "https://picsum.photos/seed/wst-\(seed)/440/320") }

    var body: some View {
        AsyncImage(url: source) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            palette.accent.opacity(0.3)
        }
        .frame(width: 360, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .padding(8)
        .background(palette.accent, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
        .rotationEffect(.degrees(tilt))
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.5).delay(0.15)) { tilt = -3 }
        }
    }
}

/// A standard labeled text field that turns green once complete; `isMissing` outlines it in red.
struct PillField: View {
    let label: String
    var placeholder = ""
    @Binding var text: String
    let isDone: Bool
    var isMissing = false
    let palette: PromptPalette

    private var outline: Color { isMissing ? .red : isDone ? .green : .clear }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(isDone ? .green : palette.ink.opacity(0.85))
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title3, design: .rounded))
                .controlSize(.large)
                .padding(4)
                .background(isDone ? Color.green.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(outline, lineWidth: 2))
                .animation(.easeOut(duration: 0.2), value: isDone)
                .animation(.easeOut(duration: 0.2), value: isMissing)
        }
        .frame(width: 460)
    }
}

struct CountdownRing: View {
    let total: Double
    let remaining: Double
    let palette: PromptPalette

    var body: some View {
        Gauge(value: total - remaining, in: 0...max(total, 1)) {
            EmptyView()
        } currentValueLabel: {
            Text("\(Int(remaining.rounded(.up)))")
                .font(.system(.body, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(palette.ink)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(palette.accent)
        .scaleEffect(1.2)
        .accessibilityLabel("\(Int(remaining.rounded(.up))) seconds remaining")
    }
}

/// A standard prominent button; when `requiresHold` it becomes a custom pill that fills while pressed and only fires after a 2 second long press.
struct ActionPill: View {
    private static let holdSeconds: Double = 2

    let title: String
    let requiresHold: Bool
    let isEnabled: Bool
    var isDefault = false
    let palette: PromptPalette
    let action: () -> Void
    /// Called when the user tries the button while it is disabled.
    var onBlockedTap: () -> Void = {}

    @State private var holdStartedAt: Date?

    var body: some View {
        Group {
            if requiresHold {
                TimelineView(.animation(paused: holdStartedAt == nil)) { context in
                    pill(progress: holdStartedAt.map { min(1, context.date.timeIntervalSince($0) / Self.holdSeconds) } ?? 0)
                }
                .onLongPressGesture(minimumDuration: Self.holdSeconds, maximumDistance: 40) {
                    if isEnabled { action() }
                } onPressingChanged: { isPressing in
                    holdStartedAt = isPressing && isEnabled ? Date() : nil
                    if isPressing && !isEnabled { onBlockedTap() }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Hold to \(title)")
            } else {
                // Not `.disabled`, so a tap on an incomplete form can still flag what is missing.
                Button(title, action: isEnabled ? action : onBlockedTap)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(palette.accent)
                    .foregroundStyle(palette.onAccent)
                    .keyboardShortcut(isDefault ? .defaultAction : nil)
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
    }

    private func pill(progress: Double) -> some View {
        Label {
            Text(title)
        } icon: {
            if requiresHold { Image(systemName: "hand.tap.fill") }
        }
        .font(.system(size: 17, weight: .semibold, design: .rounded))
        .foregroundStyle(palette.onAccent)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    palette.accent.opacity(requiresHold ? 0.55 : 1)
                    palette.accent.frame(width: proxy.size.width * progress)
                }
            }
        }
        .clipShape(Capsule())
        .contentShape(Capsule())
    }
}
