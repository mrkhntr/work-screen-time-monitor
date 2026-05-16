import Foundation
import SwiftUI
import WorkScreenTimeCore

private enum SettingsPage: String, CaseIterable, Identifiable {
    case schedule
    case timing
    case messages
    case accountability
    case maintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: "Schedule"
        case .timing: "Timing"
        case .messages: "Messages"
        case .accountability: "Accountability"
        case .maintenance: "Maintenance"
        }
    }

    var systemImage: String {
        switch self {
        case .schedule: "calendar"
        case .timing: "timer"
        case .messages: "text.quote"
        case .accountability: "paperplane"
        case .maintenance: "wrench.and.screwdriver"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft: AppConfig
    @State private var quotesText: String
    @State private var statusMessage = ""
    @State private var selectedPage: SettingsPage? = .schedule

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
                            Toggle("Dismissals with reasons", isOn: webhookBinding(\.isEnabled))
                                .toggleStyle(.switch)
                        }
                        rowDivider(columns: 2)
                        GridRow {
                            rowLabel("POST URL")
                            TextField("https://example.com/hook", text: webhookBinding(\.endpointURLString))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 420)
                        }
                    }
                }

                settingsPanel("Authentication") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            rowLabel("Bearer token")
                            SecureField("Optional", text: webhookBinding(\.bearerToken))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 420)
                        }
                        rowDivider(columns: 2)
                        GridRow {
                            rowLabel("API key")
                            SecureField("Optional", text: webhookBinding(\.apiKey))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 420)
                        }
                    }
                    .disabled(!webhookIsEnabled)
                    .opacity(webhookIsEnabled ? 1 : 0.48)
                }

                settingsPanel("Message") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            rowLabel("Template")
                            TextField("I dismissed Work Screen Time because: {{reason}}", text: webhookBinding(\.messageTemplate))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 420)
                        }
                        rowDivider(columns: 2)
                        GridRow {
                            Text("")
                            Button {
                                save()
                                Task {
                                    statusMessage = await model.sendTestAccountabilityWebhook()
                                }
                            } label: {
                                Label("Send Test", systemImage: "paperplane.fill")
                            }
                        }
                    }
                    .disabled(!webhookIsEnabled)
                    .opacity(webhookIsEnabled ? 1 : 0.48)
                }
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

    private func save() {
        draft.quotes = pendingQuotes
        model.saveConfig(draft)
        statusMessage = "Saved."
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
