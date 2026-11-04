import Foundation

enum PausePointKind: String, CaseIterable {
    case breathe
    case remind
}

enum PromptAction: CaseIterable {
    case quickSnooze
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
    /// True briefly after the user tries to act with required fields unfinished, so those fields flash.
    @Published var showMissing = false
    private var clearMissingTask: Task<Void, Never>?
    @Published var action: PromptAction = .snooze

    init(pauseKind: PausePointKind? = nil) {
        self.pauseKind = pauseKind ?? PausePointKind.allCases.randomElement() ?? .breathe
    }

    func flagMissing() {
        clearMissingTask?.cancel()
        showMissing = true
        clearMissingTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            showMissing = false
        }
    }
}
