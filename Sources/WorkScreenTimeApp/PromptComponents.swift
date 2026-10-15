import AppKit
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

    @State private var localImage: NSImage?
    @State private var tilt: Double = 0

    var body: some View {
        Group {
            if let url {
                if let localImage {
                    Image(nsImage: localImage).resizable().aspectRatio(contentMode: .fill)
                } else {
                    palette.accent.opacity(0.3)
                        .task(id: url) { localImage = NSImage(contentsOf: url) }
                }
            } else {
                // Seeded so every display shows the same photo.
                AsyncImage(url: URL(string: "https://picsum.photos/seed/wst-\(seed)/440/320")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    palette.accent.opacity(0.3)
                }
            }
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

/// A text field whose label stays visible above it while typing.
struct PillField: View {
    let label: String
    var placeholder = ""
    @Binding var text: String
    let isDone: Bool
    let palette: PromptPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(label)
            } icon: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? palette.accent : palette.ink.opacity(0.4))
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.ink.opacity(0.85))
            .padding(.leading, 6)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isDone)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(palette.ink.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(palette.accent.opacity(isDone ? 0.9 : 0.4), lineWidth: 1.5))
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

/// A filled pill button; when `requiresHold` it fills while pressed and only fires after a 2 second long press.
struct ActionPill: View {
    private static let holdSeconds: Double = 2

    let title: String
    let requiresHold: Bool
    let isEnabled: Bool
    var isDefault = false
    let palette: PromptPalette
    let action: () -> Void

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
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Hold to \(title)")
            } else {
                Button(action: action) { pill(progress: 0) }
                    .buttonStyle(.plain)
                    .keyboardShortcut(isDefault ? .defaultAction : nil)
                    .disabled(!isEnabled)
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
