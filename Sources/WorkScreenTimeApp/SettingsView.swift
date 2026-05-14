import Foundation
import SwiftUI
import WorkScreenTimeCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft: AppConfig
    @State private var quotesText: String
    @State private var statusMessage = ""

    init(model: AppModel) {
        self.model = model
        let config = model.editableConfig
        _draft = State(initialValue: config)
        _quotesText = State(initialValue: config.quotes.joined(separator: "\n"))
    }

    var body: some View {
        Form {
            Section("Downtime Schedule") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    ForEach(draft.schedules.indices, id: \.self) { index in
                        GridRow {
                            Toggle(draft.schedules[index].weekday.displayName, isOn: $draft.schedules[index].isEnabled)
                                .frame(width: 180, alignment: .leading)
                            timePicker(for: index, keyPath: \.start)
                            Text("to")
                                .foregroundStyle(.secondary)
                            timePicker(for: index, keyPath: \.end)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Timing") {
                Stepper(value: $draft.warningLeadMinutes, in: 0...120) {
                    Text("Warning lead: \(draft.warningLeadMinutes) minutes")
                }
                Stepper(value: $draft.snoozeMinutes, in: 1...120) {
                    Text("Snooze: \(draft.snoozeMinutes) minutes")
                }
                Stepper(value: $draft.idleThresholdMinutes, in: 1...60) {
                    Text("Idle threshold: \(draft.idleThresholdMinutes) minutes")
                }
            }

            Section("Quotes and Messages") {
                TextEditor(text: $quotesText)
                    .font(.body)
                    .frame(minHeight: 120)
            }

            Section {
                HStack {
                    Button("Save") {
                        save()
                    }
                    Button("Reset to Current") {
                        resetDraft()
                    }
                    Button("Clear History") {
                        model.clearHistory()
                        statusMessage = "History cleared."
                    }
                    Button("Clear Today's History") {
                        model.clearTodayHistory()
                        statusMessage = "Today's history cleared."
                    }
                    Button("Open Config Folder") {
                        model.openConfigFolder()
                    }
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onReceive(model.$config) { config in
            draft = config
            quotesText = config.quotes.joined(separator: "\n")
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
        .frame(width: 120)
    }

    private func save() {
        let quotes = quotesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        draft.quotes = quotes.isEmpty ? AppConfig.defaultQuotes : quotes
        model.saveConfig(draft)
        statusMessage = "Saved."
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
