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
            PromptWindowCoordinator(model: model) {
                Label(model.menuTitle, systemImage: model.menuSystemImage)
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 760, minHeight: 640)
        }

        Window("Work Screen Time Prompt", id: PromptWindowIDs.prompt) {
            PromptWindowScene(model: model)
                .windowDismissBehavior(.disabled)
                .windowMinimizeBehavior(.disabled)
                .windowResizeBehavior(.disabled)
                .windowFullScreenBehavior(.disabled)
                .persistentSystemOverlays(.hidden)
        }
        .windowLevel(.floating)
        .defaultLaunchBehavior(.suppressed)
        .defaultWindowPlacement { _, context in
            let bounds = context.defaultDisplay.bounds
            return WindowPlacement(
                CGPoint(x: bounds.minX, y: bounds.minY),
                size: bounds.size
            )
        }
    }
}

private struct PromptWindowCoordinator<LabelContent: View>: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @ViewBuilder let label: () -> LabelContent
    @State private var openedPromptID: UUID?

    var body: some View {
        label()
            .task {
                syncPromptWindow(with: model.activePrompt?.id)
            }
            .onChange(of: model.activePrompt?.id) { _, promptID in
                syncPromptWindow(with: promptID)
            }
    }

    private func syncPromptWindow(with promptID: UUID?) {
        if let promptID {
            guard openedPromptID != promptID else { return }
            openedPromptID = promptID
            openWindow(id: PromptWindowIDs.prompt)
        } else if openedPromptID != nil {
            openedPromptID = nil
            dismissWindow(id: PromptWindowIDs.prompt)
        }
    }
}

private enum PromptWindowIDs {
    static let prompt = "prompt"
}

private struct PromptWindowScene: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if let prompt = model.activePrompt {
                FullScreenPromptView(
                    config: prompt.config,
                    escalation: prompt.escalation,
                    onSnooze: { model.snoozeActivePrompt() },
                    onDismiss: { model.dismissActivePrompt(reason: $0) }
                )
            } else {
                Color(red: 0.08, green: 0.08, blue: 0.085)
                    .ignoresSafeArea()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
