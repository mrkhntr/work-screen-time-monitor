import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import WorkScreenTimeCore

/// Thin native shell over the shared TypeScript brain (`core.js` via JSCoreHost).
/// It feeds events (tick / foreground change / user actions) with a resolved
/// `now`, persists the returned state blob, and executes the returned effects
/// (overlay, notifications, webhook, scheduling, menu status). All decisions —
/// schedule, escalation, app-blocking, webhook payloads — live in the core.
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
    private let engine = ScheduleEngine()
    private let idleMonitor = IdleMonitor()
    private let notificationManager = NotificationManager()
    private let accountabilityWebhookNotifier = AccountabilityWebhookNotifier()
    private let webhookSender = WebhookSender()
    private let jsCore = JSCoreHost()

    private var coreStateJSON: String
    private var settingsWindow: NSWindow?
    private var promptController: PromptWindowController?
    private var wakeTimer: Timer?
    private var countdownTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var started = false

    init(paths: AppPaths = AppPaths()) {
        self.paths = paths
        try? paths.ensureDirectoryExists()
        self.configStore = ConfigStore(url: paths.configURL)
        self.config = configStore.load()
        if let data = try? Data(contentsOf: paths.stateURL),
           let stored = String(data: data, encoding: .utf8), !stored.isEmpty {
            self.coreStateJSON = stored
        } else {
            self.coreStateJSON = JSCoreHost()?.defaultStateJSON() ?? "{}"
        }
        Self.shared = self
        start()
    }

    // MARK: - Public computed

    var isPromptShowing: Bool { promptController != nil }
    var menuTitle: String { todaySnoozeCount > 0 ? "Balance \(todaySnoozeCount)" : "Balance" }
    var configDirectoryURL: URL { paths.applicationSupportDirectory }
    var editableConfig: AppConfig { config }

    // MARK: - Lifecycle

    func start() {
        guard !started else { tick(); return }
        started = true
        notificationManager.requestAuthorization()
        notificationManager.scheduleWarnings(config: config)
        installWorkspaceObserver()
        tick()
    }

    func stop() {
        wakeTimer?.invalidate(); wakeTimer = nil
        countdownTimer?.invalidate(); countdownTimer = nil
        removeWorkspaceObserver()
        closePrompt()
    }

    // MARK: - User actions

    func startResumeCountdown() {
        guard resumeCountdown == nil else { return }
        resumeCountdown = 5
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let current = self.resumeCountdown else { return }
                if current <= 1 {
                    self.cancelResume()
                    self.resumeNow()
                } else {
                    self.resumeCountdown = current - 1
                }
            }
        }
        if let countdownTimer { RunLoop.main.add(countdownTimer, forMode: .common) }
    }

    func cancelResume() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        resumeCountdown = nil
    }

    func pauseForOneHour() { dispatch(event: ["type": "pauseRequested", "kind": "hour"]) }
    func pauseUntilTomorrow() { dispatch(event: ["type": "pauseRequested", "kind": "tomorrow"]) }

    func enforceNow() {
        guard !isPromptShowing else { return }
        cancelResume()
        dispatch(event: ["type": "enforceNow"])
    }

    func resumeNow() {
        cancelResume()
        dispatch(event: ["type": "resumeNow"])
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

    func openConfigFolder() { NSWorkspace.shared.open(configDirectoryURL) }

    func saveConfig(_ newConfig: AppConfig) {
        try? configStore.save(newConfig)
        config = configStore.load()
        notificationManager.scheduleWarnings(config: config)
        tick()
    }

    func clearHistory() {
        coreStateJSON = jsCore?.defaultStateJSON() ?? "{}"
        persistState()
        closePrompt()
        tick()
    }

    func clearTodayHistory() {
        let now = Date()
        let window = engine.activeWindow(at: now, config: config)
        let dateKey = window.map { engine.dateKey(for: $0.start) } ?? engine.dateKey(for: now)
        if var obj = decodedState(),
           var history = obj["history"] as? [String: Any],
           var summaries = history["dailySummaries"] as? [String: Any] {
            summaries.removeValue(forKey: dateKey)
            history["dailySummaries"] = summaries
            obj["history"] = history
            if let data = try? JSONSerialization.data(withJSONObject: obj),
               let s = String(data: data, encoding: .utf8) {
                coreStateJSON = s
                persistState()
            }
        }
        closePrompt()
        tick()
    }

    func sendTestNotification() { notificationManager.sendTest() }

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

    // MARK: - Core bridge

    private func tick() {
        let idle = Int(idleMonitor.secondsSinceLastInput().rounded())
        dispatch(event: ["type": "tick", "idleSeconds": idle])
    }

    private func nowJSON() -> String {
        let epochMs = Int((Date().timeIntervalSince1970 * 1000).rounded())
        let tzOffsetMin = TimeZone.current.secondsFromGMT() / 60
        return "{\"epochMs\":\(epochMs),\"tzOffsetMin\":\(tzOffsetMin)}"
    }

    private func configJSON() -> String {
        guard let data = try? JSONEncoder().encode(config), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    private func decodedState() -> [String: Any]? {
        guard let data = coreStateJSON.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func persistState() {
        try? coreStateJSON.data(using: .utf8)?.write(to: paths.stateURL, options: [.atomic])
    }

    private func dispatch(event: [String: Any]) {
        guard let jsCore,
              let eventData = try? JSONSerialization.data(withJSONObject: event),
              let eventJSON = String(data: eventData, encoding: .utf8) else { return }

        let resultJSON = jsCore.reduce(state: coreStateJSON, event: eventJSON, now: nowJSON(), config: configJSON())
        guard let data = resultJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let state = obj["state"],
           let stateData = try? JSONSerialization.data(withJSONObject: state),
           let stateString = String(data: stateData, encoding: .utf8) {
            coreStateJSON = stateString
            persistState()
        }

        for effect in (obj["effects"] as? [[String: Any]]) ?? [] {
            apply(effect)
        }
    }

    // MARK: - Effects

    private func num(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

    private func apply(_ effect: [String: Any]) {
        switch effect["type"] as? String {
        case "showOverlay":
            applyShowOverlay(effect)
        case "hideOverlay":
            closePrompt()
        case "notifySnoozed":
            if let ms = num(effect["untilMs"]) {
                notificationManager.notifySnoozed(until: Date(timeIntervalSince1970: ms / 1000))
            }
        case "sendWebhook":
            if let request = effect["request"] as? [String: Any] { webhookSender.send(request) }
        case "scheduleWake":
            if let ms = num(effect["atEpochMs"]) { scheduleWake(atEpochMs: ms) }
        case "setStatus":
            applyStatus(effect)
        default:
            break
        }
    }

    private func applyShowOverlay(_ effect: [String: Any]) {
        guard let escDict = effect["escalation"] as? [String: Any],
              let escData = try? JSONSerialization.data(withJSONObject: escDict),
              let escalation = try? JSONDecoder().decode(EscalationState.self, from: escData) else { return }

        let dateKey = (effect["dateKey"] as? String) ?? ""
        let windowDict = effect["window"] as? [String: Any]
        let id = (windowDict?["id"] as? String) ?? "window"
        let weekdayRaw = Int(num(windowDict?["weekday"]) ?? 2)
        let startMs = num(windowDict?["startMs"]) ?? (Date().timeIntervalSince1970 * 1000)
        let endMs = num(windowDict?["endMs"]) ?? (startMs + 3_600_000)
        let window = DowntimeWindow(
            id: id,
            weekday: Weekday(rawValue: weekdayRaw) ?? .monday,
            start: Date(timeIntervalSince1970: startMs / 1000),
            end: Date(timeIntervalSince1970: endMs / 1000)
        )

        closePrompt()
        let controller = PromptWindowController(
            window: window,
            dateKey: dateKey,
            config: config,
            escalation: escalation,
            onSnooze: { [weak self] _, reason in self?.dispatch(event: ["type": "userSnoozed", "reason": reason ?? NSNull()]) },
            onDismiss: { [weak self] _, reason in self?.dispatch(event: ["type": "userDismissed", "reason": reason ?? NSNull()]) }
        )
        promptController = controller
        controller.show()
    }

    private func applyStatus(_ effect: [String: Any]) {
        var text = (effect["text"] as? String) ?? statusText
        if text.hasSuffix("until"), let ms = num(effect["untilMs"]) {
            text += " " + shortTime(Date(timeIntervalSince1970: ms / 1000))
        }
        statusText = text
        menuSystemImage = (effect["icon"] as? String) ?? menuSystemImage
        todaySnoozeCount = Int(num(effect["snoozeCount"]) ?? Double(todaySnoozeCount))
        showsPauseActions = (effect["showsPauseActions"] as? Bool) ?? showsPauseActions
        showsResumeAction = (effect["showsResumeAction"] as? Bool) ?? showsResumeAction
    }

    private func closePrompt() {
        promptController?.closeAll()
        promptController = nil
    }

    private func scheduleWake(atEpochMs: Double) {
        let fireDate = Date(timeIntervalSince1970: atEpochMs / 1000)
        let interval = max(1, fireDate.timeIntervalSinceNow)
        wakeTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        wakeTimer = timer
    }

    private func installWorkspaceObserver() {
        guard workspaceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier else { return }
            Task { @MainActor in self?.dispatch(event: ["type": "foregroundChanged", "appId": bundleId]) }
        }
    }

    private func removeWorkspaceObserver() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
