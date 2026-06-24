import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingPanelView>?
    private var lastContentSize = NSSize.zero
    private var hasPlacedInitially = false

    /// 悬浮窗底边与 Dock 可见区域顶部的间距
    private let dockTopMargin: CGFloat = 12

    var isVisible: Bool { panel?.isVisible == true }

    func show(store: StatusStore) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 44),
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            self.panel = panel
        }

        if hostingView == nil {
            let hosting = NSHostingView(rootView: FloatingPanelView(store: store))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            panel?.contentView = hosting
            hostingView = hosting
        }

        if !hasPlacedInitially {
            resizeToFitContent(preserveCenter: false)
            positionAboveDockCentered()
            hasPlacedInitially = true
        } else {
            resizeToFitContent(preserveCenter: true)
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle(store: StatusStore) {
        if isVisible {
            hide()
        } else {
            show(store: store)
        }
    }

    func refreshLayout(store: StatusStore) {
        guard isVisible else { return }
        // @Observable 会自动刷新视图；内容尺寸变化时以当前位置为中心缩放
        resizeToFitContent(preserveCenter: true)
    }

    func updateAutoHide(store: StatusStore, autoHideWhenIdle: Bool) {
        guard autoHideWhenIdle else { return }
        if store.activeCount == 0 && store.pendingCount == 0 && store.recentCount == 0 {
            hide()
        }
    }

    private func resizeToFitContent(preserveCenter: Bool) {
        guard let hostingView, let panel else { return }
        hostingView.layoutSubtreeIfNeeded()

        let fitted = hostingView.fittingSize
        let clampedWidth = min(
            max(fitted.width, FloatingPanelLayout.minWidth),
            FloatingPanelLayout.maxWidth
        )
        let newSize = NSSize(
            width: clampedWidth,
            height: max(fitted.height, 44)
        )

        // 尺寸没变就不动窗口，避免每秒重复 setFrame 导致抖动
        if abs(newSize.width - lastContentSize.width) < 0.5,
           abs(newSize.height - lastContentSize.height) < 0.5 {
            return
        }
        lastContentSize = newSize

        let oldFrame = panel.frame
        var newFrame = NSRect(origin: oldFrame.origin, size: newSize)

        if preserveCenter {
            let centerX = oldFrame.midX
            let centerY = oldFrame.midY
            newFrame.origin.x = centerX - newSize.width / 2
            newFrame.origin.y = centerY - newSize.height / 2
        }

        panel.setFrame(newFrame, display: true)
    }

    /// 水平居中，紧贴 Dock 可见区域上方（`visibleFrame` 已排除 Dock 与菜单栏）
    private func positionAboveDockCentered() {
        guard let panel else { return }

        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let size = panel.frame.size

        let x = visible.midX - size.width / 2
        let y = visible.minY + dockTopMargin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
