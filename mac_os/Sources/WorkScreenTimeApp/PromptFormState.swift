import Foundation

enum PromptAction {
    case snooze
    case dismiss

    var alternate: PromptAction {
        switch self {
        case .snooze: .dismiss
        case .dismiss: .snooze
        }
    }

    func title(snoozeMinutes: Int) -> String {
        switch self {
        case .snooze: "Snooze now"
        case .dismiss: "Dismiss for today"
        }
    }
}

@MainActor
final class PromptFormState: ObservableObject {
    @Published var holdUnlocked = false
    @Published var phrase = ""
    @Published var reason = ""
    @Published var selectedAction: PromptAction = .snooze
    @Published var attemptedAction = false
}
