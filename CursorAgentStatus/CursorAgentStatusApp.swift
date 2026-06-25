import AppKit
import SwiftUI

@MainActor
enum AppServices {
    static let store = StatusStore()
    static let tailer = EventTailer()
    static let panelController = FloatingPanelController()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLaunchCoordinator.startIfNeeded(
            store: AppServices.store,
            tailer: AppServices.tailer,
            panelController: AppServices.panelController
        )
    }

    /// 菜单栏 App 被多次 open / ⌘R 时会叠加进程；保留当前实例，退出其余副本。
    private func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            guard app.processIdentifier != currentPID else { continue }
            if !app.forceTerminate() {
                app.terminate()
            }
        }
    }
}

@main
struct CursorAgentStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showFloatingPanel") private var showFloatingPanel = true

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                store: AppServices.store,
                showFloatingPanel: $showFloatingPanel
            )
            .onChange(of: showFloatingPanel) { _, visible in
                AppLaunchCoordinator.setFloatingPanelVisible(
                    visible,
                    store: AppServices.store,
                    panelController: AppServices.panelController
                )
            }
        } label: {
            MenuBarIconView(store: AppServices.store)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarIconView: View {
    @Bindable var store: StatusStore

    var body: some View {
        StatusBadgeView(
            iconName: store.statusIconName,
            activeCount: store.activeCount
        )
    }
}
