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

            Button("Enforce Now") {
                model.enforceNow()
            }

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

            Divider()

            CheckForUpdatesView(updater: updater)

            Button(model.launchAtLogin ? "Disable Launch at Login" : "Enable Launch at Login") {
                model.toggleLaunchAtLogin()
            }

            Menu("Advanced") {
                Button("Send Test Notification") {
                    model.sendTestNotification()
                }

                Button("Open Config Folder") {
                    model.openConfigFolder()
                }
            }

            Button("Quit") {
                model.quit()
            }
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
