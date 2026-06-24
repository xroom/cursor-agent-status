import SwiftUI

@main
struct CursorAgentStatusApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("showFloatingPanel") private var showFloatingPanel = true

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                store: appState.store,
                showFloatingPanel: $showFloatingPanel
            )
            .onChange(of: showFloatingPanel) { _, visible in
                AppLaunchCoordinator.setFloatingPanelVisible(
                    visible,
                    store: appState.store,
                    panelController: appState.panelController
                )
            }
        } label: {
            StatusBadgeView(
                iconName: appState.store.statusIconName,
                activeCount: appState.store.activeCount
            )
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppState: ObservableObject {
    let store = StatusStore()
    let tailer = EventTailer()
    let panelController = FloatingPanelController()

    init() {
        AppLaunchCoordinator.startIfNeeded(
            store: store,
            tailer: tailer,
            panelController: panelController
        )
    }
}
