import AppKit
import SwiftUI

/// 应用启动时初始化事件管道与悬浮窗，避免依赖菜单栏下拉视图是否展开。
@MainActor
enum AppLaunchCoordinator {
    private static var didStart = false

    static func startIfNeeded(
        store: StatusStore,
        tailer: EventTailer,
        panelController: FloatingPanelController
    ) {
        guard !didStart else { return }
        didStart = true

        store.bootstrap(from: tailer)
        store.onStateChange = {
            refreshFloatingPanels(store: store, panelController: panelController)
        }

        tailer.onEvent = { event in
            Task { @MainActor in
                store.handle(event)
            }
        }
        tailer.start()

        // 悬浮窗创建推迟到下一轮 runloop，避免 SwiftUI Scene 尚未就绪时测量 NSHostingView
        DispatchQueue.main.async {
            refreshFloatingPanels(store: store, panelController: panelController)
        }
    }

    static func refreshFloatingPanels(
        store: StatusStore,
        panelController: FloatingPanelController
    ) {
        let showFloatingPanel = UserDefaults.standard.object(forKey: "showFloatingPanel") as? Bool ?? true
        if showFloatingPanel {
            if panelController.isVisible {
                panelController.refreshLayout(store: store)
            } else {
                panelController.show(store: store)
            }
        }
    }

    static func setFloatingPanelVisible(
        _ visible: Bool,
        store: StatusStore,
        panelController: FloatingPanelController
    ) {
        if visible {
            panelController.show(store: store)
        } else {
            panelController.hide()
        }
    }
}
