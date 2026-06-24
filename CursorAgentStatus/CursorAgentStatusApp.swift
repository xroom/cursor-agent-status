import SwiftUI

@main
struct CursorAgentStatusApp: App {
    @State private var store = StatusStore()
    @AppStorage("showFloatingPanel") private var showFloatingPanel = true
    @State private var autoHideWhenIdle = false

    private let tailer = EventTailer()
    private let panelController = FloatingPanelController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                store: store,
                showFloatingPanel: $showFloatingPanel
            )
            .onAppear {
                setupEventPipeline()
                if showFloatingPanel {
                    panelController.show(store: store)
                }
            }
            .onChange(of: showFloatingPanel) { _, visible in
                if visible {
                    panelController.show(store: store)
                } else {
                    panelController.hide()
                }
            }
            .onChange(of: store.revision) { _, _ in
                panelController.refreshLayout(store: store)
                panelController.updateAutoHide(store: store, autoHideWhenIdle: autoHideWhenIdle)
            }
        } label: {
            StatusBadgeView(iconName: store.statusIconName, activeCount: store.activeCount)
        }
        .menuBarExtraStyle(.window)
    }

    private func setupEventPipeline() {
        store.bootstrap(from: tailer)
        tailer.onEvent = { event in
            Task { @MainActor in
                store.handle(event)
            }
        }
        tailer.start()
    }
}
