import AppKit
import SwiftUI
import WorkScreenTimeCore

@MainActor
final class PromptWindowController {
    let downtimeWindow: DowntimeWindow
    let dateKey: String

    private let config: AppConfig
    private let escalation: EscalationState
    private let onSnooze: (PromptWindowController) -> Void
    private let onDismiss: (PromptWindowController, String?) -> Void
    private var windows: [NSWindow] = []
    private var didFinish = false

    init(
        window: DowntimeWindow,
        dateKey: String,
        config: AppConfig,
        escalation: EscalationState,
        onSnooze: @escaping (PromptWindowController) -> Void,
        onDismiss: @escaping (PromptWindowController, String?) -> Void
    ) {
        self.downtimeWindow = window
        self.dateKey = dateKey
        self.config = config
        self.escalation = escalation
        self.onSnooze = onSnooze
        self.onDismiss = onDismiss
    }

    func show() {
        windows = NSScreen.screens.map { screen in
            let view = FullScreenPromptView(
                config: config,
                escalation: escalation,
                onSnooze: { [weak self] in self?.finishSnooze() },
                onDismiss: { [weak self] reason in self?.finishDismiss(reason: reason) }
            )

            let window = PromptWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.contentView = NSHostingView(rootView: view)
            window.backgroundColor = .black
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            return window
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func closeAll() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func finishSnooze() {
        guard !didFinish else { return }
        didFinish = true
        onSnooze(self)
    }

    private func finishDismiss(reason: String?) {
        guard !didFinish else { return }
        didFinish = true
        onDismiss(self, reason)
    }
}

private final class PromptWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

