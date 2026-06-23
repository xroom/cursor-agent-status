import SwiftUI

@main
struct CursorAgentStatusApp: App {
    @State private var store = StatusStore()
    @State private var isFloatingPanelVisible = false
    @State private var isAlwaysOnTop = true
    @State private var panelOpacity = 0.95
    @State private var autoHideWhenIdle = false

    private let tailer = EventTailer()
    private let panelController = FloatingPanelController()

    init() {
        // Event wiring happens in onAppear because @State isn't ready here.
    }

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
                    panelController.show(
                        store: store,
                        isAlwaysOnTop: $isAlwaysOnTop,
                        opacity: $panelOpacity,
                        autoHideWhenIdle: $autoHideWhenIdle
                    )
                } else {
                    panelController.hide()
                }
            }
            .onChange(of: store.activeCount) { _, _ in
                panelController.updateAutoHide(store: store, autoHideWhenIdle: autoHideWhenIdle)
            }
            .onChange(of: store.pendingCount) { _, _ in
                panelController.updateAutoHide(store: store, autoHideWhenIdle: autoHideWhenIdle)
            }
            .onChange(of: store.recentCount) { _, _ in
                panelController.updateAutoHide(store: store, autoHideWhenIdle: autoHideWhenIdle)
            }
            .onChange(of: isAlwaysOnTop) { _, value in
                panelController.applyWindowSettings(isAlwaysOnTop: value, opacity: panelOpacity)
            }
            .onChange(of: panelOpacity) { _, value in
                panelController.applyWindowSettings(isAlwaysOnTop: isAlwaysOnTop, opacity: value)
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
