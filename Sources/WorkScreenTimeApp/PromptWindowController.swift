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
    private var screenChangeObserver: NSObjectProtocol?
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
        installScreenChangeObserverIfNeeded()
        rebuildWindowsForCurrentScreens()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeAll() {
        windows.forEach { $0.close() }
        windows.removeAll()
        removeScreenChangeObserver()
    }

    deinit {
        removeScreenChangeObserver()
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

    private func installScreenChangeObserverIfNeeded() {
        guard screenChangeObserver == nil else { return }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildWindowsForCurrentScreens()
        }
    }

    private func removeScreenChangeObserver() {
        guard let screenChangeObserver else { return }
        NotificationCenter.default.removeObserver(screenChangeObserver)
        self.screenChangeObserver = nil
    }

    private func rebuildWindowsForCurrentScreens() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map(makeWindow(for:))
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
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
}

private final class PromptWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
