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

private final class PanelMoveDelegate: NSObject, NSWindowDelegate {
    let panelId: String
    weak var controller: FloatingPanelController?

    init(panelId: String, controller: FloatingPanelController) {
        self.panelId = panelId
        self.controller = controller
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        controller?.handlePanelMove(panelId: panelId, frame: window.frame)
    }
}

@MainActor
final class FloatingPanelController: NSObject {
    private var panels: [String: AgentPanelWindow] = [:]
    private var panelDelegates: [String: PanelMoveDelegate] = [:]
    private var isEnabled = false
    private var lastOrderedIds: [String] = []
    private var groupAnchorLeft: CGFloat?
    private var groupBaselineY: CGFloat?
    private var isApplyingLayout = false
    private var layoutTimer: Timer?

    /// 悬浮窗底边与 Dock 可见区域顶部的间距
    private let dockTopMargin: CGFloat = 12
    /// 吸附间距：窗口并排时保持的固定间隙
    private let snapGap: CGFloat = 8
    /// 拖拽时触发磁吸的距离阈值
    private let snapThreshold: CGFloat = 28

    var isVisible: Bool { panels.values.contains { $0.panel.isVisible } }

    func show(store: StatusStore) {
        isEnabled = true
        startLayoutTimer()
        sync(store: store)
    }

    func hide() {
        isEnabled = false
        stopLayoutTimer()
        for entry in panels.values {
            entry.panel.delegate = nil
            entry.panel.orderOut(nil)
        }
        panels.removeAll()
        panelDelegates.removeAll()
        lastOrderedIds = []
        groupAnchorLeft = nil
        groupBaselineY = nil
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

    func handlePanelMove(panelId: String, frame: NSRect) {
        guard !isApplyingLayout, panels.count > 1 else { return }
        guard let index = lastOrderedIds.firstIndex(of: panelId) else { return }

        let snapped = snapMovedFrame(frame, movedIndex: index, orderedIds: lastOrderedIds)
        layoutDockedPanels(
            orderedIds: lastOrderedIds,
            baselineY: snapped.origin.y,
            anchorPanelIndex: index,
            anchorX: snapped.origin.x,
            display: true
        )
    }

    private func sync(store: StatusStore) {
        let agents = store.activeFloatingAgents()
        let activeIds = Set(agents.map(\.panelId))
        let orderedIds = agents.map(\.panelId)

        for id in panels.keys where !activeIds.contains(id) {
            panels[id]?.panel.delegate = nil
            panels[id]?.panel.orderOut(nil)
            panels.removeValue(forKey: id)
            panelDelegates.removeValue(forKey: id)
        }

        let hadMultipleBefore = lastOrderedIds.count > 1
        let anchorBefore = groupAnchorLeft

        for content in agents {
            upsertPanel(content: content, store: store)
        }

        if agents.isEmpty {
            panels.values.forEach { $0.panel.orderOut(nil) }
            panels.removeAll()
            panelDelegates.removeAll()
            lastOrderedIds = []
            groupAnchorLeft = nil
            groupBaselineY = nil
        } else {
            lastOrderedIds = orderedIds
            if hadMultipleBefore, panels.count > 1, let anchorBefore {
                layoutDockedPanels(
                    orderedIds: orderedIds,
                    anchorLeft: anchorBefore,
                    baselineY: groupBaselineY,
                    display: true
                )
            } else {
                layoutDockedPanels(orderedIds: orderedIds, centerOnScreen: true, display: true)
            }
        }
    }

    private func upsertPanel(content: AgentFloatingContent, store: StatusStore) {
        let panelId = content.panelId

        if let existing = panels[panelId] {
            existing.hostingView.rootView = FloatingPanelView(
                store: store,
                conversationId: content.conversationId
            )
            _ = remeasurePanel(existing)
            if !existing.panel.isVisible {
                existing.panel.orderFrontRegardless()
            }
            return
        }

        let panel = makePanel(panelId: panelId)
        let hosting = NSHostingView(
            rootView: FloatingPanelView(store: store, conversationId: content.conversationId)
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        let entry = AgentPanelWindow(panelId: panelId, panel: panel, hostingView: hosting)
        panels[panelId] = entry
        panel.orderFrontRegardless()
        _ = remeasurePanel(entry)
    }

    private func makePanel(panelId: String) -> NSPanel {
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

        let delegate = PanelMoveDelegate(panelId: panelId, controller: self)
        panelDelegates[panelId] = delegate
        panel.delegate = delegate
        return panel
    }

    @discardableResult
    private func remeasurePanel(_ entry: AgentPanelWindow) -> Bool {
        guard entry.panel.contentView != nil else { return false }

        let fitted = entry.hostingView.fittingSize
        let clampedWidth = min(max(fitted.width, 1), FloatingPanelLayout.maxWidth)
        let newSize = NSSize(width: clampedWidth, height: max(fitted.height, 48))

        let changed =
            abs(newSize.width - entry.lastContentSize.width) >= 0.5
            || abs(newSize.height - entry.lastContentSize.height) >= 0.5
        entry.lastContentSize = newSize
        return changed
    }

    private func panelSizes(for entries: [AgentPanelWindow]) -> [NSSize] {
        entries.map { entry in
            let measured = entry.lastContentSize
            let width = max(measured.width, entry.panel.frame.width, 1)
            let height = max(measured.height, entry.panel.frame.height, 48)
            return NSSize(width: width, height: height)
        }
    }

    private func layoutDockedPanels(
        orderedIds: [String],
        centerOnScreen: Bool = false,
        anchorLeft: CGFloat? = nil,
        baselineY: CGFloat? = nil,
        anchorPanelIndex: Int? = nil,
        anchorX: CGFloat? = nil,
        display: Bool
    ) {
        guard !orderedIds.isEmpty else { return }

        let entries = orderedIds.compactMap { panels[$0] }
        guard entries.count == orderedIds.count else { return }

        for entry in entries {
            _ = remeasurePanel(entry)
        }

        let sizes = panelSizes(for: entries)
        let gap = snapGap * CGFloat(max(entries.count - 1, 0))
        let totalWidth = sizes.map(\.width).reduce(0, +) + gap

        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame

        let y = baselineY ?? groupBaselineY ?? (visible.minY + dockTopMargin)
        groupBaselineY = y

        let startX: CGFloat
        if let anchorPanelIndex, let anchorX {
            var left = anchorX
            for i in 0..<anchorPanelIndex {
                left -= snapGap + sizes[i].width
            }
            startX = left
        } else if let anchorLeft {
            startX = anchorLeft
        } else if centerOnScreen || groupAnchorLeft == nil {
            startX = visible.midX - totalWidth / 2
        } else {
            startX = groupAnchorLeft ?? (visible.midX - totalWidth / 2)
        }

        groupAnchorLeft = startX

        isApplyingLayout = true
        defer { isApplyingLayout = false }

        var x = startX
        for (index, entry) in entries.enumerated() {
            let size = sizes[index]
            let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            entry.panel.setFrame(frame, display: display)
            x += size.width + snapGap
        }
    }

    private func snapMovedFrame(_ frame: NSRect, movedIndex: Int, orderedIds: [String]) -> NSRect {
        let entries = orderedIds.compactMap { panels[$0] }
        guard movedIndex < entries.count else { return frame }

        let sizes = panelSizes(for: entries)
        let screen = NSScreen.main ?? NSScreen.screens.first
        let defaultY = screen.map { $0.visibleFrame.minY + dockTopMargin } ?? frame.origin.y
        var snapped = frame
        snapped.origin.y = groupBaselineY ?? defaultY

        guard entries.count > 1 else { return snapped }

        if movedIndex > 0 {
            let leftNeighbor = entries[movedIndex - 1].panel.frame
            let targetLeft = leftNeighbor.maxX + snapGap
            if abs(snapped.origin.x - targetLeft) <= snapThreshold {
                snapped.origin.x = targetLeft
            }
        }

        if movedIndex < entries.count - 1 {
            let rightNeighbor = entries[movedIndex + 1].panel.frame
            let targetLeft = rightNeighbor.minX - snapGap - sizes[movedIndex].width
            if abs(snapped.origin.x - targetLeft) <= snapThreshold {
                snapped.origin.x = targetLeft
            }
        }

        return snapped
    }

    private func startLayoutTimer() {
        guard layoutTimer == nil else { return }
        layoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDockedSizesIfNeeded()
            }
        }
    }

    private func stopLayoutTimer() {
        layoutTimer?.invalidate()
        layoutTimer = nil
    }

    private func refreshDockedSizesIfNeeded() {
        guard isEnabled, panels.count > 0, !lastOrderedIds.isEmpty else { return }

        var changed = false
        for id in lastOrderedIds {
            guard let entry = panels[id] else { continue }
            if remeasurePanel(entry) {
                changed = true
            }
        }

        guard changed else { return }
        layoutDockedPanels(
            orderedIds: lastOrderedIds,
            anchorLeft: groupAnchorLeft,
            baselineY: groupBaselineY,
            display: true
        )
    }
}
