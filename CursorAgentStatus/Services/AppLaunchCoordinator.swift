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

        store.prepareForLiveEvents()
        panelController.hide()

        store.onStateChange = {
            refreshFloatingPanels(store: store, panelController: panelController)
        }

        tailer.onEvent = { event in
            Task { @MainActor in
                store.handle(event)
            }
        }

        tailer.start()
    }

    static func refreshFloatingPanels(
        store: StatusStore,
        panelController: FloatingPanelController
    ) {
        let showFloatingPanel = UserDefaults.standard.object(forKey: "showFloatingPanel") as? Bool ?? true
        guard showFloatingPanel else {
            panelController.hide()
            return
        }

        guard !store.activeFloatingAgents().isEmpty else {
            panelController.hide()
            return
        }

        // 推迟到下一轮 runloop；执行前再次确认仍有活跃 HUD 会话，避免 stop 后旧的 async show 误触发
        DispatchQueue.main.async {
            guard !store.activeFloatingAgents().isEmpty else {
                panelController.hide()
                return
            }
            if panelController.isActive {
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
