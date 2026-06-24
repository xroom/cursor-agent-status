import AppKit
import SwiftUI

private final class AgentPanelWindow {
    let panelId: String
    let panel: NSPanel
    var hostingView: NSHostingView<FloatingPanelView>
    var lastContentSize = NSSize.zero

    init(panelId: String, panel: NSPanel, hostingView: NSHostingView<FloatingPanelView>) {
        self.panelId = panelId
        self.panel = panel
        self.hostingView = hostingView
    }
}

@MainActor
final class FloatingPanelController: NSObject {
    private var panels: [String: AgentPanelWindow] = [:]
    private var isEnabled = false

    /// 悬浮窗底边与 Dock 可见区域顶部的间距
    private let dockTopMargin: CGFloat = 12
    private let panelGap: CGFloat = 12

    var isVisible: Bool { panels.values.contains { $0.panel.isVisible } }

    func show(store: StatusStore) {
        isEnabled = true
        sync(store: store)
    }

    func hide() {
        isEnabled = false
        for entry in panels.values {
            entry.panel.orderOut(nil)
        }
        panels.removeAll()
    }

    func toggle(store: StatusStore) {
        if isEnabled && isVisible {
            hide()
        } else {
            show(store: store)
        }
    }

    func refreshLayout(store: StatusStore) {
        guard isEnabled else { return }
        sync(store: store)
    }

    func updateAutoHide(store: StatusStore, autoHideWhenIdle: Bool) {
        guard autoHideWhenIdle else { return }
        if store.activeCount == 0 && store.pendingCount == 0 && store.recentCount == 0 {
            hide()
        }
    }

    private func sync(store: StatusStore) {
        let agents = store.activeFloatingAgents()
        let activeIds = Set(agents.map(\.panelId))

        for id in panels.keys where !activeIds.contains(id) {
            panels[id]?.panel.orderOut(nil)
            panels.removeValue(forKey: id)
        }

        for content in agents {
            upsertPanel(content: content, store: store)
        }

        if agents.isEmpty {
            panels.values.forEach { $0.panel.orderOut(nil) }
            panels.removeAll()
        } else {
            layoutPanels(orderedIds: agents.map(\.panelId))
        }
    }

    private func upsertPanel(content: AgentFloatingContent, store: StatusStore) {
        let panelId = content.panelId

        if let existing = panels[panelId] {
            existing.hostingView.rootView = FloatingPanelView(
                store: store,
                conversationId: content.conversationId
            )
            resizePanel(existing, preservePosition: true)
            if !existing.panel.isVisible {
                existing.panel.orderFrontRegardless()
            }
            return
        }

        let panel = makePanel()
        let hosting = NSHostingView(
            rootView: FloatingPanelView(store: store, conversationId: content.conversationId)
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        let entry = AgentPanelWindow(panelId: panelId, panel: panel, hostingView: hosting)
        panels[panelId] = entry

        resizePanel(entry, preservePosition: false)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 52),
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
        return panel
    }

    private func resizePanel(_ entry: AgentPanelWindow, preservePosition: Bool) {
        entry.hostingView.layoutSubtreeIfNeeded()

        let fitted = entry.hostingView.fittingSize
        let clampedWidth = min(fitted.width, FloatingPanelLayout.maxWidth)
        let newSize = NSSize(width: clampedWidth, height: max(fitted.height, 48))

        if abs(newSize.width - entry.panel.frame.width) < 0.5,
           abs(newSize.height - entry.panel.frame.height) < 0.5 {
            entry.lastContentSize = newSize
            return
        }
        entry.lastContentSize = newSize

        let oldFrame = entry.panel.frame
        var newFrame = NSRect(origin: oldFrame.origin, size: newSize)

        if preservePosition {
            let topY = oldFrame.maxY
            newFrame.origin.x = oldFrame.origin.x
            newFrame.origin.y = topY - newSize.height
        }

        entry.panel.setFrame(newFrame, display: true)
    }

    private func layoutPanels(orderedIds: [String]) {
        guard !orderedIds.isEmpty else { return }

        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let entries = orderedIds.compactMap { panels[$0] }
        guard !entries.isEmpty else { return }

        let widths = entries.map(\.lastContentSize.width)
        let totalWidth = widths.reduce(0, +) + panelGap * CGFloat(max(entries.count - 1, 0))
        var x = visible.midX - totalWidth / 2
        let y = visible.minY + dockTopMargin

        for (index, entry) in entries.enumerated() {
            let width = widths[index]
            var frame = entry.panel.frame
            if abs(frame.width - width) > 0.5 {
                frame.size.width = width
                entry.panel.setFrame(frame, display: false)
            }
            entry.panel.setFrameOrigin(NSPoint(x: x, y: y))
            x += width + panelGap
        }
    }
}
