import SwiftUI

@main
struct CursorAgentStatusApp: App {
    @State private var store = StatusStore()
    @State private var isFloatingPanelVisible = false
    @State private var autoHideWhenIdle = false

    private let tailer = EventTailer()
    private let panelController = FloatingPanelController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                store: store,
                isFloatingPanelVisible: $isFloatingPanelVisible
            )
            .onAppear {
                setupEventPipeline()
            }
            .onChange(of: isFloatingPanelVisible) { _, visible in
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
