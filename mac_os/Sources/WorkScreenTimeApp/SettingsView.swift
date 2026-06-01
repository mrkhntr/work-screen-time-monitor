import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WorkScreenTimeCore

private enum SettingsPage: String, CaseIterable, Identifiable {
    case schedule
    case timing
    case messages
    case accountability
    case blocking
    case maintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: "Schedule"
        case .timing: "Timing"
        case .messages: "Messages"
        case .accountability: "Accountability"
        case .blocking: "Blocking"
        case .maintenance: "Maintenance"
        }
    }

    var systemImage: String {
        switch self {
        case .schedule: "calendar"
        case .timing: "timer"
        case .messages: "text.quote"
        case .accountability: "paperplane"
        case .blocking: "hand.raised"
        case .maintenance: "wrench.and.screwdriver"
        }
    }
}

private enum WebhookTestState: Equatable {
    case idle
    case sending
    case succeeded
    case failed
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft: AppConfig
    @State private var quotesText: String
    @State private var statusMessage = ""
    @State private var selectedPage: SettingsPage? = .schedule
    @State private var webhookTestState: WebhookTestState = .idle
    @State private var webhookTestMessage = ""

    init(model: AppModel) {
        self.model = model
        let config = model.editableConfig
        _draft = State(initialValue: config)
        _quotesText = State(initialValue: config.quotes.joined(separator: "\n"))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        pageHeader
                        pageContent
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if hasUnsavedChanges || !statusMessage.isEmpty {
                Divider()
                footer
            }
        }
        .onReceive(model.$config) { config in
            draft = config
            quotesText = config.quotes.joined(separator: "\n")
        }
    }

    private var currentPage: SettingsPage {
        selectedPage ?? .schedule
    }

    private var sidebar: some View {
        List(SettingsPage.allCases, selection: $selectedPage) { page in
            Label(page.title, systemImage: page.systemImage)
                .tag(page)
        }
        .listStyle(.sidebar)
        .frame(width: 220)
        .background(.bar)
    }

    private var pendingQuotes: [String] {
        let quotes = quotesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return quotes.isEmpty ? AppConfig.defaultQuotes : quotes
    }

    private var hasUnsavedChanges: Bool {
        var normalizedDraft = draft
        normalizedDraft.quotes = pendingQuotes
        return normalizedDraft != model.config
    }

    private var webhookIsEnabled: Bool {
        draft.accountabilityWebhook?.isEnabled ?? false
    }

    private var pageHeader: some View {
        Label {
            Text(currentPage.title)
                .font(.title2.weight(.semibold))
        } icon: {
            Image(systemName: currentPage.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case .schedule:
            settingsPanel("Downtime Schedule") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                    GridRow {
                        Text("Day")
                            .gridCellColumns(2)
                            .frame(width: 170, alignment: .leading)
                        Text("Start")
                            .frame(width: 108, alignment: .leading)
                        Text("")
                            .frame(width: 24)
                        Text("End")
                            .frame(width: 108, alignment: .leading)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                    ForEach(draft.schedules.indices, id: \.self) { index in
                        GridRow {
                            Toggle("", isOn: $draft.schedules[index].isEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .frame(width: 52, alignment: .leading)

                            Text(draft.schedules[index].weekday.displayName)
                                .frame(width: 118, alignment: .leading)

                            timePicker(for: index, keyPath: \.start)
                            Text("to")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            timePicker(for: index, keyPath: \.end)
                        }

                        if index != draft.schedules.indices.last {
                            Divider()
                                .gridCellColumns(5)
                        }
                    }
                }
            }

        case .timing:
            settingsPanel("Durations") {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        rowLabel("Warning lead")
                        stepperControl(value: "\(draft.warningLeadMinutes) min", binding: $draft.warningLeadMinutes, range: 0...120)
                    }
                    rowDivider(columns: 2)
                    GridRow {
                        rowLabel("Snooze")
                        stepperControl(value: "\(draft.snoozeMinutes) min", binding: $draft.snoozeMinutes, range: 1...120)
                    }
                    rowDivider(columns: 2)
                    GridRow {
                        rowLabel("Idle threshold")
                        stepperControl(value: "\(draft.idleThresholdMinutes) min", binding: $draft.idleThresholdMinutes, range: 1...60)
                    }
                }
            }

        case .messages:
            settingsPanel("Quotes and Messages") {
                TextEditor(text: $quotesText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 240)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }

        case .accountability:
            VStack(spacing: 14) {
                settingsPanel("Webhook") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            rowLabel("Trigger")
                            Toggle("Dismissals & repeated snoozes", isOn: webhookBinding(\.isEnabled))
                                .toggleStyle(.switch)
                        }
                        rowDivider(columns: 2)
                        GridRow {
                            rowLabel("POST URL")
                            TextField("https://example.com/hook", text: webhookBinding(\.endpointURLString))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 420)
                        }
                        rowDivider(columns: 2)
                        GridRow {
                            rowLabel("Test")
                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    Task {
                                        await sendTestWebhook()
                                    }
                                } label: {
                                    webhookTestButtonLabel
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(webhookTestTint)
                                .disabled(webhookTestState == .sending)

                                if !webhookTestMessage.isEmpty {
                                    Label(webhookTestMessage, systemImage: webhookTestState == .failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(webhookTestState == .failed ? .red : .green)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(width: 420, alignment: .leading)
                                }
                            }
                        }
                    }
                }

                settingsPanel("Authentication") {
                    headersEditor
                    .disabled(!webhookIsEnabled)
                    .opacity(webhookIsEnabled ? 1 : 0.48)
                }

                settingsPanel("Message") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            rowLabel("Template")
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("I {{event}} Work Screen Time because: {{reason}}", text: webhookBinding(\.messageTemplate))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 420)
                                templateHelpText
                                placeholderWarningText
                            }
                        }
                        rowDivider(columns: 2)
                        GridRow {
                            rowLabel("Extra keys")
                            VStack(alignment: .leading, spacing: 6) {
                                bodyFieldsEditor
                                templateHelpText
                                placeholderWarningText
                            }
                        }
                    }
                    .disabled(!webhookIsEnabled)
                    .opacity(webhookIsEnabled ? 1 : 0.48)
                }
            }

        case .blocking:
            VStack(spacing: 14) {
                settingsPanel("App Blocking") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            rowLabel("Enable")
                            Toggle("Block apps during downtime", isOn: blockingBinding(\.isEnabled))
                                .toggleStyle(.switch)
                        }
                        rowDivider(columns: 2)
                        GridRow {
                            rowLabel("Scope")
                            Toggle("Block every app, not just the list below", isOn: blockingBinding(\.blockAllApps))
                        }
                    }
                }

                settingsPanel("Blocked Apps") {
                    VStack(alignment: .leading, spacing: 10) {
                        let apps = draft.appBlocking?.blockedApps ?? []
                        if apps.isEmpty {
                            Text("No apps added yet. Add the apps you want walled off during downtime.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(apps.indices, id: \.self) { index in
                            HStack(spacing: 10) {
                                Toggle("", isOn: blockedAppEnabledBinding(index))
                                    .labelsHidden()
                                Text(apps[index].displayName.isEmpty ? apps[index].identifier : apps[index].displayName)
                                Text(apps[index].identifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(role: .destructive) {
                                    removeBlockedApp(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button {
                            addBlockedApps()
                        } label: {
                            Label("Add app…", systemImage: "plus")
                        }
                    }
                    .disabled(!(draft.appBlocking?.isEnabled ?? false))
                    .opacity((draft.appBlocking?.isEnabled ?? false) ? 1 : 0.48)
                }

                Text("Opening a blocked app during downtime shows the full-screen prompt. macOS blocking is overlay-only — no apps are force-quit — so it needs no extra permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .maintenance:
            settingsPanel("Maintenance") {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        rowLabel("History")
                        HStack(spacing: 8) {
                            Button {
                                model.clearTodayHistory()
                                statusMessage = "Today's history cleared."
                            } label: {
                                Label("Today", systemImage: "calendar.badge.minus")
                            }

                            Button(role: .destructive) {
                                model.clearHistory()
                                statusMessage = "History cleared."
                            } label: {
                                Label("All", systemImage: "trash")
                            }
                        }
                    }
                    rowDivider(columns: 2)
                    GridRow {
                        rowLabel("Files")
                        Button {
                            model.openConfigFolder()
                        } label: {
                            Label("Open Config Folder", systemImage: "folder")
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !statusMessage.isEmpty {
                Label(statusMessage, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                resetDraft()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .disabled(!hasUnsavedChanges)

            Button {
                save()
            } label: {
                Label("Save", systemImage: "checkmark")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!hasUnsavedChanges)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func settingsPanel<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 118, alignment: .trailing)
    }

    private var templateHelpText: some View {
        Text("Available: {{message}}, {{reason}}, {{event}}, {{timestamp}}, {{dateKey}}, {{windowID}}, {{snoozeCount}}, {{app}}")
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 420, alignment: .leading)
    }

    @ViewBuilder
    private var placeholderWarningText: some View {
        if !unknownWebhookPlaceholders.isEmpty {
            Label(
                "Unknown placeholders: \(unknownWebhookPlaceholders.map { "{{\($0)}}" }.joined(separator: ", "))",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 420, alignment: .leading)
        }
    }

    @ViewBuilder
    private var webhookTestButtonLabel: some View {
        switch webhookTestState {
        case .idle:
            Label("Send Test", systemImage: "paperplane.fill")
        case .sending:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text("Sending")
            }
        case .succeeded:
            Label("Sent", systemImage: "checkmark.circle.fill")
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
        }
    }

    private var webhookTestTint: Color {
        switch webhookTestState {
        case .idle, .sending:
            .accentColor
        case .succeeded:
            .green
        case .failed:
            .red
        }
    }

    private var unknownWebhookPlaceholders: [String] {
        let webhook = draft.accountabilityWebhook ?? AccountabilityWebhookConfig()
        var foundPlaceholders = placeholders(in: webhook.messageTemplate)
        for field in webhook.bodyFields {
            foundPlaceholders.formUnion(placeholders(in: field.value))
        }
        return foundPlaceholders.subtracting(Self.allowedWebhookPlaceholders).sorted()
    }

    private static let allowedWebhookPlaceholders: Set<String> = [
        "app",
        "event",
        "message",
        "timestamp",
        "dateKey",
        "windowID",
        "snoozeCount",
        "reason",
        "dismissalReason"
    ]

    private func placeholders(in template: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{\s*([A-Za-z0-9_]+)\s*\}\}"#) else {
            return []
        }
        let range = NSRange(template.startIndex..<template.endIndex, in: template)
        let matches = regex.matches(in: template, range: range)
        return Set(matches.compactMap { match in
            guard let placeholderRange = Range(match.range(at: 1), in: template) else { return nil }
            return String(template[placeholderRange])
        })
    }

    private var headersEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Menu {
                    Button("x-api-key") {
                        addWebhookHeader(name: "x-api-key")
                    }
                    Button("Authorization") {
                        addWebhookHeader(name: "Authorization", value: "Bearer ")
                    }
                    Button("Content-Type") {
                        addWebhookHeader(name: "Content-Type", value: "application/json")
                    }
                    Divider()
                    Button("Blank Header") {
                        addWebhookHeader()
                    }
                } label: {
                    Label("Add Header", systemImage: "plus")
                }
            }

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text("")
                        .frame(width: 26)
                    Text("Key")
                        .frame(width: 150, alignment: .leading)
                    Text("Value")
                        .frame(width: 260, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

                ForEach(webhookHeaders.wrappedValue.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Toggle("", isOn: webhookHeaders[index].isEnabled)
                            .labelsHidden()
                            .frame(width: 26)

                        TextField("Header", text: webhookHeaders[index].name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)

                        SecureField("Value", text: webhookHeaders[index].value)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)

                        Button {
                            removeWebhookHeader(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var bodyFieldsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                addWebhookBodyField()
            } label: {
                Label("Add Body Key", systemImage: "plus")
            }

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text("")
                        .frame(width: 26)
                    Text("Key")
                        .frame(width: 150, alignment: .leading)
                    Text("Value")
                        .frame(width: 260, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 26)
                    Text("message")
                        .frame(width: 150, alignment: .leading)
                    Text("Rendered from Template")
                        .foregroundStyle(.secondary)
                        .frame(width: 260, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .font(.callout)

                ForEach(webhookBodyFields.wrappedValue.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Toggle("", isOn: webhookBodyFields[index].isEnabled)
                            .labelsHidden()
                            .frame(width: 26)

                        TextField("groupId", text: webhookBodyFields[index].key)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)

                        TextField("ad@g.us", text: webhookBodyFields[index].value)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)

                        Button {
                            removeWebhookBodyField(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func rowDivider(columns: Int) -> some View {
        Divider()
            .gridCellColumns(columns)
            .padding(.leading, 136)
            .padding(.vertical, 2)
    }

    private func stepperControl(
        value: String,
        binding: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 10) {
            Text(value)
                .monospacedDigit()
                .frame(width: 70, alignment: .leading)

            Stepper("", value: binding, in: range)
                .labelsHidden()
        }
    }

    private func timePicker(for index: Int, keyPath: WritableKeyPath<DaySchedule, TimeOfDay>) -> some View {
        DatePicker(
            "",
            selection: Binding(
                get: {
                    date(for: draft.schedules[index][keyPath: keyPath])
                },
                set: { date in
                    draft.schedules[index][keyPath: keyPath] = timeOfDay(from: date)
                }
            ),
            displayedComponents: .hourAndMinute
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .frame(width: 112)
    }

    private func save(showStatus: Bool = true) {
        draft.quotes = pendingQuotes
        model.saveConfig(draft)
        if showStatus {
            statusMessage = "Saved."
        }
    }

    private func blockingBinding<Value>(_ keyPath: WritableKeyPath<AppBlockingConfig, Value>) -> Binding<Value> {
        Binding(
            get: { (draft.appBlocking ?? AppBlockingConfig())[keyPath: keyPath] },
            set: { newValue in
                var blocking = draft.appBlocking ?? AppBlockingConfig()
                blocking[keyPath: keyPath] = newValue
                draft.appBlocking = blocking
            }
        )
    }

    private func blockedAppEnabledBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: {
                let apps = draft.appBlocking?.blockedApps ?? []
                return apps.indices.contains(index) ? apps[index].isEnabled : false
            },
            set: { newValue in
                var blocking = draft.appBlocking ?? AppBlockingConfig()
                guard blocking.blockedApps.indices.contains(index) else { return }
                blocking.blockedApps[index].isEnabled = newValue
                draft.appBlocking = blocking
            }
        )
    }

    private func addBlockedApps() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }

        var blocking = draft.appBlocking ?? AppBlockingConfig()
        for url in panel.urls {
            guard let identifier = Bundle(url: url)?.bundleIdentifier else { continue }
            if blocking.blockedApps.contains(where: { $0.identifier == identifier }) { continue }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            blocking.blockedApps.append(BlockedApp(identifier: identifier, displayName: name))
        }
        draft.appBlocking = blocking
    }

    private func removeBlockedApp(at index: Int) {
        var blocking = draft.appBlocking ?? AppBlockingConfig()
        guard blocking.blockedApps.indices.contains(index) else { return }
        blocking.blockedApps.remove(at: index)
        draft.appBlocking = blocking
    }

    private func sendTestWebhook() async {
        guard webhookTestState != .sending else { return }
        save(showStatus: false)
        statusMessage = ""
        webhookTestState = .sending
        webhookTestMessage = ""

        let result = await model.sendTestAccountabilityWebhook()
        webhookTestState = result.isSuccess ? .succeeded : .failed
        webhookTestMessage = result.message
    }

    private func webhookBinding<Value>(_ keyPath: WritableKeyPath<AccountabilityWebhookConfig, Value>) -> Binding<Value> {
        Binding(
            get: {
                (draft.accountabilityWebhook ?? AccountabilityWebhookConfig())[keyPath: keyPath]
            },
            set: { newValue in
                var webhook = draft.accountabilityWebhook ?? AccountabilityWebhookConfig()
                webhook[keyPath: keyPath] = newValue
                draft.accountabilityWebhook = webhook
            }
        )
    }

    private var webhookHeaders: Binding<[AccountabilityWebhookHeader]> {
        Binding(
            get: {
                draft.accountabilityWebhook?.headers ?? []
            },
            set: { newValue in
                var webhook = draft.accountabilityWebhook ?? AccountabilityWebhookConfig()
                webhook.headers = newValue
                draft.accountabilityWebhook = webhook
            }
        )
    }

    private var webhookBodyFields: Binding<[AccountabilityWebhookBodyField]> {
        Binding(
            get: {
                draft.accountabilityWebhook?.bodyFields ?? []
            },
            set: { newValue in
                var webhook = draft.accountabilityWebhook ?? AccountabilityWebhookConfig()
                webhook.bodyFields = newValue
                draft.accountabilityWebhook = webhook
            }
        )
    }

    private func addWebhookHeader(name: String = "", value: String = "") {
        var headers = webhookHeaders.wrappedValue
        headers.append(AccountabilityWebhookHeader(name: name, value: value))
        webhookHeaders.wrappedValue = headers
    }

    private func removeWebhookHeader(at index: Int) {
        var headers = webhookHeaders.wrappedValue
        guard headers.indices.contains(index) else { return }
        headers.remove(at: index)
        webhookHeaders.wrappedValue = headers
    }

    private func addWebhookBodyField(key: String = "", value: String = "") {
        var fields = webhookBodyFields.wrappedValue
        fields.append(AccountabilityWebhookBodyField(key: key, value: value))
        webhookBodyFields.wrappedValue = fields
    }

    private func removeWebhookBodyField(at index: Int) {
        var fields = webhookBodyFields.wrappedValue
        guard fields.indices.contains(index) else { return }
        fields.remove(at: index)
        webhookBodyFields.wrappedValue = fields
    }

    private func resetDraft() {
        draft = model.editableConfig
        quotesText = draft.quotes.joined(separator: "\n")
        statusMessage = "Reset."
    }

    private func date(for time: TimeOfDay) -> Date {
        Calendar.autoupdatingCurrent.date(
            bySettingHour: time.hour,
            minute: time.minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private func timeOfDay(from date: Date) -> TimeOfDay {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}
