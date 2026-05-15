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
    private var isRebuildingWindows = false
    private var needsAnotherRebuild = false
    private var lastScreenSignature: [ScreenSignature] = []
    private let screenSignaturePrecision = 100.0
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
        requestRebuildForCurrentScreens()
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
            self?.requestRebuildForCurrentScreens()
        }
    }

    private func removeScreenChangeObserver() {
        guard let screenChangeObserver else { return }
        NotificationCenter.default.removeObserver(screenChangeObserver)
        self.screenChangeObserver = nil
    }

    private func requestRebuildForCurrentScreens() {
        assert(Thread.isMainThread)
        guard !didFinish else { return }
        let screenSignature = currentScreenSignature()
        if !windows.isEmpty, screenSignature == lastScreenSignature {
            return
        }
        guard !isRebuildingWindows else {
            needsAnotherRebuild = true
            return
        }
        isRebuildingWindows = true
        defer {
            isRebuildingWindows = false
            if needsAnotherRebuild {
                needsAnotherRebuild = false
                requestRebuildForCurrentScreens()
            }
        }
        rebuildWindowsForCurrentScreens(screenSignature: screenSignature)
    }

    private func rebuildWindowsForCurrentScreens(screenSignature: [ScreenSignature]) {
        windows.forEach { $0.close() }
        windows.removeAll()
        lastScreenSignature = screenSignature
        windows = NSScreen.screens.map(makeWindow(for:))
    }

    private func currentScreenSignature() -> [ScreenSignature] {
        NSScreen.screens
            .map { screen in
                let frame = screen.frame
                return ScreenSignature(
                    x: Int((frame.origin.x * screenSignaturePrecision).rounded()),
                    y: Int((frame.origin.y * screenSignaturePrecision).rounded()),
                    width: Int((frame.size.width * screenSignaturePrecision).rounded()),
                    height: Int((frame.size.height * screenSignaturePrecision).rounded()),
                    scale: Int((screen.backingScaleFactor * screenSignaturePrecision).rounded())
                )
            }
            .sorted()
    }

    private struct ScreenSignature: Hashable, Comparable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let scale: Int

        static func < (lhs: ScreenSignature, rhs: ScreenSignature) -> Bool {
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            if lhs.width != rhs.width { return lhs.width < rhs.width }
            if lhs.height != rhs.height { return lhs.height < rhs.height }
            return lhs.scale < rhs.scale
        }
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
