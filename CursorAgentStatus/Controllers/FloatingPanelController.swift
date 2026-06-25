import AppKit
import SwiftUI

private extension NSScreen {
    var placementIdentifier: String {
        if let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "screen-\(number.intValue)"
        }
        return String(format: "frame-%.0f-%.0f", frame.origin.x, frame.origin.y)
    }
}

private enum FloatingPanelPlacement {
    private static let screenIdKey = "floatingPanelScreenId"
    private static let anchorLeftKey = "floatingPanelAnchorLeft"
    private static let baselineYKey = "floatingPanelBaselineY"
    private static let userAdjustedKey = "floatingPanelUserAdjusted"

    static var savedScreenId: String? {
        UserDefaults.standard.string(forKey: screenIdKey)
    }

    static var isUserAdjusted: Bool {
        UserDefaults.standard.bool(forKey: userAdjustedKey)
    }

    static var savedAnchorLeft: CGFloat? {
        guard UserDefaults.standard.object(forKey: anchorLeftKey) != nil else { return nil }
        return CGFloat(UserDefaults.standard.double(forKey: anchorLeftKey))
    }

    static var savedBaselineY: CGFloat? {
        guard UserDefaults.standard.object(forKey: baselineYKey) != nil else { return nil }
        return CGFloat(UserDefaults.standard.double(forKey: baselineYKey))
    }

    static func rememberScreen(_ screenId: String) {
        UserDefaults.standard.set(screenId, forKey: screenIdKey)
    }

    static func saveUserPlacement(screenId: String, anchorLeft: CGFloat, baselineY: CGFloat) {
        UserDefaults.standard.set(screenId, forKey: screenIdKey)
        UserDefaults.standard.set(Double(anchorLeft), forKey: anchorLeftKey)
        UserDefaults.standard.set(Double(baselineY), forKey: baselineYKey)
        UserDefaults.standard.set(true, forKey: userAdjustedKey)
    }
}

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
    private var preferredLayoutScreen: NSScreen?

    /// 悬浮窗底边与 Dock 可见区域顶部的间距
    private let dockTopMargin: CGFloat = 12
    /// 吸附间距：窗口并排时保持的固定间隙
    private let snapGap: CGFloat = 8
    /// 拖拽时触发磁吸的距离阈值
    private let snapThreshold: CGFloat = 28
    /// 面板尚未完成 SwiftUI 布局时的兜底尺寸
    private let defaultPanelSize = NSSize(width: 300, height: 52)

    var isActive: Bool { isEnabled }
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
        guard !isApplyingLayout else { return }
        guard let index = lastOrderedIds.firstIndex(of: panelId) else { return }

        if panels.count > 1 {
            let snapped = snapMovedFrame(frame, movedIndex: index, orderedIds: lastOrderedIds)
            preferredLayoutScreen = screenContaining(point: frame.origin)
            layoutDockedPanels(
                orderedIds: lastOrderedIds,
                anchorPanelIndex: index,
                anchorX: snapped.origin.x,
                display: true
            )
            preferredLayoutScreen = nil
            persistUserPlacement(for: snapped)
            return
        }

        let screen = screenContaining(point: frame.origin) ?? resolvedLayoutScreen()
        let visible = screen.visibleFrame
        var snapped = frame
        snapped.origin.y = dockBaselineY(in: visible)
        snapped.origin.x = centeredAnchorLeft(in: visible, totalWidth: snapped.width)
        groupBaselineY = snapped.origin.y
        groupAnchorLeft = snapped.origin.x

        isApplyingLayout = true
        panels[panelId]?.panel.setFrame(snapped, display: true)
        isApplyingLayout = false

        persistUserPlacement(for: snapped)
    }

    private func sync(store: StatusStore) {
        let agents = store.visibleFloatingAgents()
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
                    display: true
                )
            } else {
                layoutDockedPanels(orderedIds: orderedIds, snapToDockCenter: true, display: true)
            }
            scheduleDeferredRelayout()
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

        // 仅在窗口已展示后测量，避免 App 初始化阶段触发 AttributeGraph 崩溃
        if entry.panel.isVisible {
            entry.hostingView.layoutSubtreeIfNeeded()
        }

        var fitted = entry.hostingView.fittingSize
        if !fitted.width.isFinite || fitted.width <= 1 || fitted.width == NSView.noIntrinsicMetric {
            fitted.width = defaultPanelSize.width
        }
        if !fitted.height.isFinite || fitted.height <= 1 || fitted.height == NSView.noIntrinsicMetric {
            fitted.height = defaultPanelSize.height
        }

        let clampedWidth = min(max(fitted.width, 200), FloatingPanelLayout.maxWidth)
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
        snapToDockCenter: Bool = false,
        anchorLeft: CGFloat? = nil,
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

        let screen = resolvedLayoutScreen(for: entries.map(\.panel.frame))
        let visible = screen.visibleFrame
        let y = dockBaselineY(in: visible)
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
        } else if snapToDockCenter || groupAnchorLeft == nil {
            startX = centeredAnchorLeft(in: visible, totalWidth: totalWidth)
        } else {
            startX = groupAnchorLeft ?? centeredAnchorLeft(in: visible, totalWidth: totalWidth)
        }

        let clampedStartX = min(max(startX, visible.minX), max(visible.minX, visible.maxX - totalWidth))
        groupAnchorLeft = clampedStartX

        FloatingPanelPlacement.rememberScreen(screen.placementIdentifier)

        isApplyingLayout = true
        defer { isApplyingLayout = false }

        var x = clampedStartX
        for (index, entry) in entries.enumerated() {
            let size = sizes[index]
            let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            entry.panel.setFrame(frame, display: display)
            x += size.width + snapGap
        }
    }

    /// Dock 可见区域上方、面板底边的 Y 坐标
    private func dockBaselineY(in visible: NSRect) -> CGFloat {
        visible.minY + dockTopMargin
    }

    /// 面板组在 Dock 上方水平居中时的左边缘 X
    private func centeredAnchorLeft(in visible: NSRect, totalWidth: CGFloat) -> CGFloat {
        min(max(visible.midX - totalWidth / 2, visible.minX), max(visible.minX, visible.maxX - totalWidth))
    }

    private func snapMovedFrame(_ frame: NSRect, movedIndex: Int, orderedIds: [String]) -> NSRect {
        let entries = orderedIds.compactMap { panels[$0] }
        guard movedIndex < entries.count else { return frame }

        let sizes = panelSizes(for: entries)
        let screen = screenContaining(point: frame.origin) ?? resolvedLayoutScreen(for: [frame])
        let visible = screen.visibleFrame
        var snapped = frame
        snapped.origin.y = dockBaselineY(in: visible)

        let totalWidth = sizes.map(\.width).reduce(0, +) + snapGap * CGFloat(max(entries.count - 1, 0))
        let centeredLeft = centeredAnchorLeft(in: visible, totalWidth: totalWidth)
        var groupLeft = snapped.origin.x
        for i in 0..<movedIndex {
            groupLeft -= snapGap + sizes[i].width
        }
        if abs(groupLeft - centeredLeft) <= snapThreshold {
            var alignedLeft = centeredLeft
            for i in 0..<movedIndex {
                alignedLeft += snapGap + sizes[i].width
            }
            snapped.origin.x = alignedLeft
        }

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
            display: true
        )
    }

    /// SwiftUI 首帧渲染完成后再测量一次，修正启动时 fittingSize 过小的问题
    private func scheduleDeferredRelayout() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEnabled, !self.lastOrderedIds.isEmpty else { return }
            var changed = false
            for id in self.lastOrderedIds {
                guard let entry = self.panels[id] else { continue }
                if self.remeasurePanel(entry) {
                    changed = true
                }
            }
            guard changed else { return }
            self.layoutDockedPanels(
                orderedIds: self.lastOrderedIds,
                anchorLeft: self.groupAnchorLeft,
                display: true
            )
        }
    }

    private func resolvedLayoutScreen(for frames: [NSRect] = []) -> NSScreen {
        if let preferredLayoutScreen {
            return preferredLayoutScreen
        }

        for frame in frames {
            if let screen = screenContaining(point: frame.origin) {
                return screen
            }
        }

        if let savedId = FloatingPanelPlacement.savedScreenId,
           let screen = NSScreen.screens.first(where: { $0.placementIdentifier == savedId }) {
            return screen
        }

        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return screen
        }

        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func screenContaining(point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func persistUserPlacement(for frame: NSRect) {
        guard let anchorLeft = groupAnchorLeft, let baselineY = groupBaselineY else { return }
        let screen = screenContaining(point: frame.origin) ?? resolvedLayoutScreen(for: [frame])
        FloatingPanelPlacement.saveUserPlacement(
            screenId: screen.placementIdentifier,
            anchorLeft: anchorLeft,
            baselineY: baselineY
        )
    }
}
