import Foundation

enum PausePointKind: String, CaseIterable {
    case breathe
    case remind
}

enum PromptAction: CaseIterable {
    case snooze
    case dismiss
}

/// Prompt state shared by every display's window, so all screens show the same pause and input.
@MainActor
final class PromptFormState: ObservableObject {
    let pauseKind: PausePointKind
    let pauseSeed = Int.random(in: 0..<10_000)
    let shownAt = Date()
    @Published var phrase = ""
    @Published var reason = ""
    @Published var action: PromptAction = .snooze

    init(pauseKind: PausePointKind? = nil) {
        self.pauseKind = pauseKind ?? PausePointKind.allCases.randomElement() ?? .breathe
    }
}
