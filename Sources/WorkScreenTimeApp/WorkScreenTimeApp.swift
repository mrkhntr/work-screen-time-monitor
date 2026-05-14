import AppKit
import Sparkle
import SwiftUI
import WorkScreenTimeCore

@main
struct WorkScreenTimeApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model, updater: updaterController.updater)
        } label: {
            Label(model.menuTitle, systemImage: model.menuSystemImage)
        }

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 760, minHeight: 640)
        }
    }
}

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared?.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppModel.shared?.isQuitting == true {
            return .terminateNow
        }
        
        // Prevent Cmd+Q from bypassing the full-screen lockdown
        if AppModel.shared?.isPromptShowing == true {
            return .terminateCancel
        }
        
        return .terminateNow
    }
}
