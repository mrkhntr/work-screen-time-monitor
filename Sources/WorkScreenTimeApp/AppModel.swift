import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import WorkScreenTimeCore

@MainActor
final class AppModel: ObservableObject {
    static weak var shared: AppModel?

    @Published private(set) var config: AppConfig
    @Published private(set) var statusText = "Starting"
    @Published private(set) var menuSystemImage = "clock"
    @Published private(set) var todaySnoozeCount = 0
    @Published private(set) var showsPauseActions = true
    @Published private(set) var showsResumeAction = false
    @Published private(set) var resumeCountdown: Int? = nil
    @Published private(set) var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    
    var isQuitting = false

    private let paths: AppPaths
    private let configStore: ConfigStore
    private let historyStore: HistoryStore
    private let engine = ScheduleEngine()
    private let idleMonitor = IdleMonitor()
    private let notificationManager = NotificationManager()
    private let accountabilityWebhookNotifier = AccountabilityWebhookNotifier()
    private var settingsWindow: NSWindow?
    private var mainTimer: Timer?
    private var countdownTimer: Timer?
    private var appState: AppState = .idle

    init(paths: AppPaths = AppPaths()) {
        self.paths = paths
        try? paths.ensureDirectoryExists()
        self.configStore = ConfigStore(url: paths.configURL)
        self.historyStore = HistoryStore(url: paths.historyURL)
        self.config = configStore.load()
        Self.shared = self
        start()
    }

    // MARK: - Public computed

    var isPromptShowing: Bool {
        if case .prompting = appState { return true }
        return false
    }

    var menuTitle: String {
        todaySnoozeCount > 0 ? "Balance \(todaySnoozeCount)" : "Balance"
    }

    var configDirectoryURL: URL { paths.applicationSupportDirectory }
    var editableConfig: AppConfig { config }

    // MARK: - Lifecycle

    func start() {
        guard mainTimer == nil else { tick(); return }
        notificationManager.requestAuthorization()
        notificationManager.scheduleWarnings(config: config)
        tick()
        scheduleNextTick()
    }

    func stop() {
        mainTimer?.invalidate()
        mainTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        closePromptIfShowing()
        appState = .idle
    }

    // MARK: - User actions

    func startResumeCountdown() {
        guard resumeCountdown == nil else { return }
        resumeCountdown = 5
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard let current = self.resumeCountdown else { return }
                if current <= 1 {
                    self.cancelResume()
                    self.resumeNow()
                } else {
                    self.resumeCountdown = current - 1
                }
            }
        }
        RunLoop.main.add(countdownTimer!, forMode: .common)
    }

    func cancelResume() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        resumeCountdown = nil
    }

    func pauseForOneHour() {
        let now = Date()
        let until = now.addingTimeInterval(3_600)
        closePromptIfShowing()
        appState = .paused(until: until)
        try? historyStore.recordPause(dateKey: engine.dateKey(for: now), until: until, at: now)
        refreshStatus(now: now)
    }

    func pauseUntilTomorrow() {
        let now = Date()
        let cal = Calendar.autoupdatingCurrent
        let until = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
        closePromptIfShowing()
        appState = .paused(until: until)
        try? historyStore.recordPause(dateKey: engine.dateKey(for: now), until: until, at: now)
        refreshStatus(now: now)
    }

    func enforceNow() {
        let now = Date()
        if case .prompting = appState {
            return
        }

        cancelResume()
        closePromptIfShowing()

        let dateKey = engine.dateKey(for: now)
        let summary = historyStore.summary(for: dateKey)
        let window = manualDowntimeWindow(at: now, dateKey: dateKey)
        showPrompt(for: window, dateKey: dateKey, summary: summary, now: now)
    }

    func resumeNow() {
        let now = Date()
        closePromptIfShowing()
        appState = .idle
        try? historyStore.recordResume(dateKey: engine.dateKey(for: now), at: now)
        if let window = engine.activeWindow(at: now, config: config) {
            try? historyStore.clearDismissal(
                dateKey: engine.dateKey(for: window.start),
                windowID: window.id,
                at: now
            )
        }
        refreshStatus(now: now)
    }

    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Work Screen Time Settings"
            window.contentView = NSHostingView(rootView: SettingsView(model: self))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openConfigFolder() {
        NSWorkspace.shared.open(configDirectoryURL)
    }

    func saveConfig(_ newConfig: AppConfig) {
        config = newConfig
        try? configStore.save(newConfig)
        notificationManager.scheduleWarnings(config: newConfig)
        refreshStatus()
        tick()
    }

    func clearHistory() {
        try? historyStore.clear()
        closePromptIfShowing()
        appState = .idle
        refreshStatus()
    }

    func clearTodayHistory() {
        let now = Date()
        let window = engine.activeWindow(at: now, config: config)
        let dateKey = window.map { engine.dateKey(for: $0.start) } ?? engine.dateKey(for: now)
        try? historyStore.clear(dateKey: dateKey)
        closePromptIfShowing()
        appState = .idle
        refreshStatus(now: now)
    }

    func sendTestNotification() {
        notificationManager.sendTest()
    }

    func sendTestAccountabilityWebhook() async -> (isSuccess: Bool, message: String) {
        do {
            try await accountabilityWebhookNotifier.sendTest(using: config.accountabilityWebhook)
            return (true, "Test webhook sent.")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func quit() {
        isQuitting = true
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Tick

    private func scheduleNextTick(now: Date = Date()) {
        let interval: TimeInterval
        switch appState {
        case .prompting:
            interval = 5
        case .downtimeNormal:
            interval = 10
        case .idle, .snoozed, .paused:
            interval = engine.activeWindow(at: now, config: config) != nil ? 10 : 60
        }
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = Date()
                self.tick(now: now)
                self.scheduleNextTick(now: now)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        mainTimer = t
    }

    private func tick(now: Date = Date()) {
        // Prompt auto-expiry check
        if case .prompting(let controller, let shownAt) = appState {
            let downtimeEnded = engine.activeWindow(at: now, config: config) == nil
            let timedOut = now.timeIntervalSince(shownAt) >= 3_600
            if downtimeEnded || timedOut {
                autoExpirePrompt(controller: controller, now: now, downtimeEnded: downtimeEnded)
            }
            refreshStatus(now: now)
            return
        }

        // Expire paused / snoozed if their time is up
        if case .paused(let until) = appState, now >= until { appState = .idle }
        if case .snoozed(let until) = appState, now >= until { appState = .idle }

        if case .paused = appState { refreshStatus(now: now); return }
        if case .snoozed = appState { refreshStatus(now: now); return }

        // Outside downtime — reset to idle
        guard let window = engine.activeWindow(at: now, config: config) else {
            appState = .idle
            refreshStatus(now: now)
            return
        }

        let windowDateKey = engine.dateKey(for: window.start)
        let summary = historyStore.summary(for: windowDateKey)

        // Window already dismissed — treat as idle
        if summary.lastDismissedWindowID == window.id {
            appState = .idle
            refreshStatus(now: now)
            return
        }

        let isActive = idleMonitor.secondsSinceLastInput() <= TimeInterval(config.idleThresholdMinutes * 60)

        switch appState {
        case .idle, .downtimeNormal:
            appState = .downtimeNormal
            if isActive {
                showPrompt(for: window, dateKey: windowDateKey, summary: summary, now: now)
            }

        case .snoozed, .paused, .prompting:
            break
        }

        refreshStatus(now: now)
    }

    // MARK: - Prompt

    private func showPrompt(for window: DowntimeWindow, dateKey: String, summary: DailySummary, now: Date) {
        let quote = config.quotes.isEmpty ? nil : config.quotes[summary.snoozes % config.quotes.count]
        let escalation = engine.escalationState(snoozeCount: summary.snoozes, config: config, quote: quote)
        try? historyStore.recordPrompt(dateKey: dateKey, windowID: window.id, at: now)

        let controller = PromptWindowController(
            window: window,
            dateKey: dateKey,
            config: config,
            escalation: escalation,
            onSnooze: { [weak self] c, reason in self?.snooze(from: c, reason: reason) },
            onDismiss: { [weak self] c, reason in self?.dismiss(from: c, reason: reason) }
        )
        appState = .prompting(controller: controller, shownAt: now)
        controller.show()
        refreshStatus(now: now)
    }

    private func manualDowntimeWindow(at now: Date, dateKey: String) -> DowntimeWindow {
        let weekday = Calendar.autoupdatingCurrent.component(.weekday, from: now)
        let end = engine.nextDowntimeWindow(at: now, config: config)?.end
            ?? now.addingTimeInterval(3_600)

        return DowntimeWindow(
            id: "manual-\(dateKey)-\(Int(now.timeIntervalSince1970))",
            weekday: Weekday(rawValue: weekday) ?? .monday,
            start: now,
            end: end
        )
    }

    private func snooze(from controller: PromptWindowController, reason: String?) {
        let now = Date()
        let until = now.addingTimeInterval(TimeInterval(config.snoozeMinutes * 60))
        try? historyStore.recordSnooze(dateKey: controller.dateKey, windowID: controller.downtimeWindow.id, until: until, at: now)
        if let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            let snoozeCount = historyStore.summary(for: controller.dateKey).snoozes
            sendAccountabilityWebhook(
                kind: .snoozed,
                timestamp: now,
                dateKey: controller.dateKey,
                windowID: controller.downtimeWindow.id,
                snoozeCount: snoozeCount,
                dismissalReason: reason
            )
        }
        notificationManager.notifySnoozed(until: until)
        controller.closeAll()
        appState = .snoozed(until: until)
        refreshStatus(now: now)
    }

    private func dismiss(from controller: PromptWindowController, reason: String?) {
        let now = Date()
        try? historyStore.recordDismissal(dateKey: controller.dateKey, windowID: controller.downtimeWindow.id, reason: reason, at: now)
        if let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            let snoozeCount = historyStore.summary(for: controller.dateKey).snoozes
            sendAccountabilityWebhook(
                kind: .dismissed,
                timestamp: now,
                dateKey: controller.dateKey,
                windowID: controller.downtimeWindow.id,
                snoozeCount: snoozeCount,
                dismissalReason: reason
            )
        }
        controller.closeAll()
        appState = .idle
        refreshStatus(now: now)
    }

    private func sendAccountabilityWebhook(
        kind: AccountabilityWebhookEventKind,
        timestamp: Date,
        dateKey: String,
        windowID: String?,
        snoozeCount: Int?,
        dismissalReason: String?
    ) {
        let webhookConfig = config.accountabilityWebhook
        let event = AccountabilityWebhookEvent(
            kind: kind,
            timestamp: timestamp,
            dateKey: dateKey,
            windowID: windowID,
            snoozeCount: snoozeCount,
            dismissalReason: dismissalReason
        )
        Task {
            try? await accountabilityWebhookNotifier.send(event, using: webhookConfig)
        }
    }

    private func autoExpirePrompt(controller: PromptWindowController, now: Date, downtimeEnded: Bool) {
        if !downtimeEnded {
            try? historyStore.recordDismissal(
                dateKey: controller.dateKey,
                windowID: controller.downtimeWindow.id,
                reason: nil,
                at: now
            )
        }
        controller.closeAll()
        appState = .idle
    }

    private func closePromptIfShowing() {
        if case .prompting(let controller, _) = appState {
            controller.closeAll()
        }
    }

    // MARK: - Status

    private func refreshStatus(now: Date = Date()) {
        let currentWindow = engine.activeWindow(at: now, config: config)
        let dateKey = currentWindow.map { engine.dateKey(for: $0.start) } ?? engine.dateKey(for: now)
        todaySnoozeCount = historyStore.summary(for: dateKey).snoozes

        switch appState {
        case .prompting:
            menuSystemImage = "exclamationmark.octagon.fill"
            statusText = "Enforcement active"
            showsPauseActions = false
            showsResumeAction = false

        case .paused(let until):
            menuSystemImage = "pause.circle.fill"
            statusText = "Paused until \(shortTime(until))"
            showsPauseActions = false
            showsResumeAction = true

        case .snoozed(let until):
            menuSystemImage = "moon.zzz.fill"
            statusText = "Snoozed until \(shortTime(until))"
            showsPauseActions = false
            showsResumeAction = true

        case .downtimeNormal:
            menuSystemImage = "moon.fill"
            statusText = "In downtime"
            showsPauseActions = true
            showsResumeAction = false

        case .idle:
            if let currentWindow {
                let summary = historyStore.summary(for: engine.dateKey(for: currentWindow.start))
                if summary.lastDismissedWindowID == currentWindow.id {
                    menuSystemImage = "checkmark.circle.fill"
                    statusText = "Dismissed for current window"
                    showsPauseActions = false
                    showsResumeAction = true
                } else {
                    menuSystemImage = "moon.fill"
                    statusText = "In downtime"
                    showsPauseActions = true
                    showsResumeAction = false
                }
            } else {
                menuSystemImage = "sun.max"
                statusText = "Outside downtime"
                showsPauseActions = true
                showsResumeAction = false
            }
        }
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}

private enum AppState {
    case idle
    case downtimeNormal
    case snoozed(until: Date)
    case paused(until: Date)
    case prompting(controller: PromptWindowController, shownAt: Date)
}
