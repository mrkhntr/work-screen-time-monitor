import AppKit
import SwiftUI
import WorkScreenTimeCore

@MainActor
final class PromptWindowController {
    let downtimeWindow: DowntimeWindow
    let dateKey: String

    private let config: AppConfig
    private let escalation: EscalationState
    private let onSnooze: (PromptWindowController, String?) -> Void
    private let onDismiss: (PromptWindowController, String?) -> Void
    private let formState = PromptFormState()
    private var windows: [NSWindow] = []
    private var screenChangeObserver: NSObjectProtocol?
    private var screenRebuildTask: Task<Void, Never>?
    private var didFinish = false

    init(
        window: DowntimeWindow,
        dateKey: String,
        config: AppConfig,
        escalation: EscalationState,
        onSnooze: @escaping (PromptWindowController, String?) -> Void,
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
        installScreenChangeObserver()
        rebuildWindowsForCurrentScreens()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeAll() {
        cancelPendingScreenRebuild()
        removeScreenChangeObserver()
        closeWindows()
    }

    private func closeWindows() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func finishSnooze(reason: String?) {
        guard !didFinish else { return }
        didFinish = true
        onSnooze(self, reason)
    }

    private func finishDismiss(reason: String?) {
        guard !didFinish else { return }
        didFinish = true
        onDismiss(self, reason)
    }

    private func installScreenChangeObserver() {
        guard screenChangeObserver == nil else { return }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleScreenRebuild()
            }
        }
    }

    private func removeScreenChangeObserver() {
        guard let screenChangeObserver else { return }
        NotificationCenter.default.removeObserver(screenChangeObserver)
        self.screenChangeObserver = nil
    }

    private func scheduleScreenRebuild() {
        guard !didFinish else { return }
        cancelPendingScreenRebuild()

        screenRebuildTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            self?.rebuildWindowsForCurrentScreens()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func cancelPendingScreenRebuild() {
        screenRebuildTask?.cancel()
        screenRebuildTask = nil
    }

    private func rebuildWindowsForCurrentScreens() {
        closeWindows()
        windows = NSScreen.screens.map(makeWindow(for:))
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let screenFrame = screen.frame
        let view = FullScreenPromptView(
            config: config,
            escalation: escalation,
            onSnooze: { [weak self] reason in self?.finishSnooze(reason: reason) },
            onDismiss: { [weak self] reason in self?.finishDismiss(reason: reason) },
            formState: formState
        )

        let window = PromptWindow(
            contentRect: NSRect(origin: .zero, size: screenFrame.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: screenFrame.size)
        hostingView.autoresizingMask = [.width, .height]

        window.contentView = hostingView
        window.backgroundColor = .black
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.setFrame(screenFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }
}

private final class PromptWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
