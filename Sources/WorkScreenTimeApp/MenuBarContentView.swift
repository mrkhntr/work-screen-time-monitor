import Sparkle
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    let updater: SPUUpdater

    var body: some View {
        Group {
            Text("Status: \(model.statusText)")
            Text("Today's snoozes: \(model.todaySnoozeCount)")

            Divider()

            Button("Settings...") {
                model.openSettings()
            }

            Divider()

            if model.showsPauseActions {
                Button("Pause for 1 Hour") {
                    model.pauseForOneHour()
                }
                Button("Pause Until Tomorrow") {
                    model.pauseUntilTomorrow()
                }
            }

            if model.showsResumeAction {
                if let countdown = model.resumeCountdown {
                    Button("Cancel Resume (\(countdown)s)") {
                        model.cancelResume()
                    }
                } else {
                    Button("Resume Now") {
                        model.startResumeCountdown()
                    }
                }
            }

            Divider()

            Button("Send Test Notification") {
                model.sendTestNotification()
            }

            CheckForUpdatesView(updater: updater)

            Button("Open Config Folder") {
                model.openConfigFolder()
            }

            Button(model.launchAtLogin ? "Disable Launch at Login" : "Enable Launch at Login") {
                model.toggleLaunchAtLogin()
            }

            Button("Quit") {
                model.quit()
            }
            .keyboardShortcut("q")
        }
    }
}

private struct CheckForUpdatesView: View {
    let updater: SPUUpdater
    @State private var canCheckForUpdates = false

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!canCheckForUpdates)
        .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheckForUpdates in
            self.canCheckForUpdates = canCheckForUpdates
        }
    }
}
