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

private final class AgentFloatingPanel: NSPanel {
    var panelId: String = ""
    weak var stackController: FloatingPanelController?
    private var mouseDownLocation: NSPoint?

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            super.mouseUp(with: event)
        }
        guard let start = mouseDownLocation else { return }
        let end = event.locationInWindow
        guard hypot(end.x - start.x, end.y - start.y) < 5 else { return }
        stackController?.handleStackClick(panelId: panelId)
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
    /// 堆叠组最底面板的底边 Y 坐标
    private var groupStackBottomY: CGFloat?
    /// 多任务时是否已展开为列表
    private var isStackExpanded = false
    private weak var statusStore: StatusStore?
    private var isApplyingLayout = false
    private var layoutTimer: Timer?
    private var preferredLayoutScreen: NSScreen?
    private var mouseMonitors: [Any] = []
    private var collapseDebounceTimer: Timer?
    private var isStackAnimating = false
    private var panelLastStatusCode: [String: ProStatusCode] = [:]

    /// 悬浮窗底边与 Dock 可见区域顶部的间距
    private let dockTopMargin: CGFloat = 12
    /// 收起时每张卡片露出的错位高度
    private let stackPeekStep: CGFloat = 10
    /// 展开时面板之间的间距
    private let snapGap: CGFloat = 8
    /// 堆叠展开/收起动画时长
    private let stackAnimationDuration: TimeInterval = 0.26
    /// 拖拽时触发磁吸的距离阈值
    private let snapThreshold: CGFloat = 28
    /// 面板尚未完成 SwiftUI 布局时的兜底尺寸
    private let defaultPanelSize = NSSize(width: 300, height: 52)

    var isActive: Bool { isEnabled }
    var isVisible: Bool { panels.values.contains { $0.panel.isVisible } }

    func show(store: StatusStore) {
        statusStore = store
        isEnabled = true
        startLayoutTimer()
        sync(store: store)
    }

    func hide() {
        isEnabled = false
        stopLayoutTimer()
        stopCollapseMonitoring()
        isStackExpanded = false
        isStackAnimating = false
        for entry in panels.values {
            entry.panel.delegate = nil
            entry.panel.orderOut(nil)
        }
        panels.removeAll()
        panelDelegates.removeAll()
        lastOrderedIds = []
        groupStackBottomY = nil
        panelLastStatusCode.removeAll()
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

    func handleStackClick(panelId: String) {
        guard !isStackExpanded, panels.count > 1, !isStackAnimating else { return }
        expandStack()
    }

    func expandStack() {
        guard !isStackExpanded, panels.count > 1, !isStackAnimating else { return }
        isStackExpanded = true
        updatePanelMovability()
        refreshAllPanelViews()
        layoutDockedPanels(
            orderedIds: lastOrderedIds,
            anchorStackBottom: groupStackBottomY,
            display: true,
            animated: true
        ) { [weak self] in
            self?.startCollapseMonitoring()
        }
    }

    func collapseStack() {
        guard isStackExpanded, !isStackAnimating else { return }
        isStackExpanded = false
        stopCollapseMonitoring()
        updatePanelMovability()
        refreshAllPanelViews()
        layoutDockedPanels(
            orderedIds: lastOrderedIds,
            anchorStackBottom: groupStackBottomY,
            display: true,
            animated: true
        )
    }

    func selectExpandedSession(panelId: String) {
        guard isStackExpanded, panels.count > 1, !isStackAnimating else { return }
        promoteSessionToFront(panelId)
        collapseStack()
    }

    private func promoteSessionToFront(_ panelId: String) {
        guard let index = lastOrderedIds.firstIndex(of: panelId), index > 0 else { return }
        var ids = lastOrderedIds
        ids.remove(at: index)
        ids.insert(panelId, at: 0)
        lastOrderedIds = ids
        statusStore?.bumpHUDSessionActivity(panelId)
    }

    private func bringSessionToFront(_ panelId: String, orderedIds: inout [String]) {
        guard let index = orderedIds.firstIndex(of: panelId), index > 0 else { return }
        orderedIds.remove(at: index)
        orderedIds.insert(panelId, at: 0)
    }

    private func promoteSessionsWithStatusChanges(
        agents: [AgentFloatingContent],
        store: StatusStore,
        orderedIds: inout [String]
    ) -> Bool {
        let activeIds = Set(agents.map(\.panelId))
        var promoted = false

        for content in agents {
            let panelId = content.panelId
            let code = content.statusCode
            if let previous = panelLastStatusCode[panelId], previous != code {
                bringSessionToFront(panelId, orderedIds: &orderedIds)
                store.bumpHUDSessionActivity(panelId)
                panels[panelId]?.panel.orderFrontRegardless()
                promoted = true
            }
            panelLastStatusCode[panelId] = code
        }

        panelLastStatusCode = panelLastStatusCode.filter { activeIds.contains($0.key) }
        return promoted
    }

    func handlePanelMove(panelId: String, frame: NSRect) {
        guard !isApplyingLayout else { return }
        guard isStackExpanded || panels.count <= 1 else { return }
        guard let index = lastOrderedIds.firstIndex(of: panelId) else { return }

        if panels.count > 1 {
            let snapped = snapMovedFrame(frame, movedIndex: index, orderedIds: lastOrderedIds)
            preferredLayoutScreen = screenContaining(point: frame.origin)
            layoutDockedPanels(
                orderedIds: lastOrderedIds,
                anchorPanelIndex: index,
                anchorY: snapped.origin.y,
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
        snapped.origin.x = centeredX(in: visible, width: snapped.width)
        groupStackBottomY = snapped.origin.y

        isApplyingLayout = true
        panels[panelId]?.panel.setFrame(snapped, display: true)
        isApplyingLayout = false

        persistUserPlacement(for: snapped)
    }

    private func sync(store: StatusStore) {
        statusStore = store
        let agents = store.visibleFloatingAgents()
        let activeIds = Set(agents.map(\.panelId))

        for id in panels.keys where !activeIds.contains(id) {
            panels[id]?.panel.delegate = nil
            panels[id]?.panel.orderOut(nil)
            panels.removeValue(forKey: id)
            panelDelegates.removeValue(forKey: id)
        }

        let hadMultipleBefore = lastOrderedIds.count > 1
        let stackBottomBefore = groupStackBottomY

        for content in agents {
            upsertPanel(content: content, store: store)
        }

        if agents.isEmpty {
            panels.values.forEach { $0.panel.orderOut(nil) }
            panels.removeAll()
            panelDelegates.removeAll()
            lastOrderedIds = []
            groupStackBottomY = nil
            panelLastStatusCode.removeAll()
        } else {
            var orderedIds = agents.map(\.panelId)
            let promotedByStatusChange = promoteSessionsWithStatusChanges(
                agents: agents,
                store: store,
                orderedIds: &orderedIds
            )
            lastOrderedIds = orderedIds
            if panels.count <= 1 {
                isStackExpanded = false
                stopCollapseMonitoring()
            }
            let shouldAnimateLayout = promotedByStatusChange && !isStackExpanded && panels.count > 1
            if hadMultipleBefore, panels.count > 1, let stackBottomBefore {
                layoutDockedPanels(
                    orderedIds: orderedIds,
                    anchorStackBottom: stackBottomBefore,
                    display: true,
                    animated: shouldAnimateLayout
                )
            } else if FloatingPanelPlacement.isUserAdjusted,
                      let savedY = FloatingPanelPlacement.savedBaselineY {
                layoutDockedPanels(
                    orderedIds: orderedIds,
                    anchorStackBottom: savedY,
                    display: true,
                    animated: shouldAnimateLayout
                )
            } else {
                layoutDockedPanels(
                    orderedIds: orderedIds,
                    snapToDock: true,
                    display: true,
                    animated: shouldAnimateLayout
                )
            }
            updatePanelMovability()
            refreshAllPanelViews()
            scheduleDeferredRelayout()
        }
    }

    private func refreshAllPanelViews() {
        guard let store = statusStore else { return }
        for (index, panelId) in lastOrderedIds.enumerated() {
            guard let entry = panels[panelId] else { continue }
            entry.hostingView.rootView = makePanelView(
                store: store,
                conversationId: panelId,
                stackIndex: index
            )
        }
    }

    private func makePanelView(store: StatusStore, conversationId: String, stackIndex: Int) -> FloatingPanelView {
        FloatingPanelView(
            store: store,
            conversationId: conversationId,
            stackCount: panels.count,
            isStackCollapsed: !isStackExpanded && panels.count > 1,
            isStackExpanded: isStackExpanded && panels.count > 1,
            showsStackBadge: !isStackExpanded && panels.count > 1 && stackIndex == 0,
            onExpandStack: { [weak self] in self?.expandStack() },
            onSelectSession: { [weak self] in self?.selectExpandedSession(panelId: conversationId) }
        )
    }

    private func updatePanelMovability() {
        let movable = isStackExpanded || panels.count <= 1
        for entry in panels.values {
            entry.panel.isMovableByWindowBackground = movable
        }
    }

    private func upsertPanel(content: AgentFloatingContent, store: StatusStore) {
        let panelId = content.panelId

        if let existing = panels[panelId] {
            let stackIndex = lastOrderedIds.firstIndex(of: panelId) ?? 0
            existing.hostingView.rootView = makePanelView(
                store: store,
                conversationId: content.conversationId ?? panelId,
                stackIndex: stackIndex
            )
            _ = remeasurePanel(existing)
            if !existing.panel.isVisible {
                existing.panel.orderFrontRegardless()
            }
            return
        }

        let panel = makePanel(panelId: panelId)
        let stackIndex = lastOrderedIds.firstIndex(of: panelId) ?? panels.count
        let hosting = NSHostingView(
            rootView: makePanelView(
                store: store,
                conversationId: content.conversationId ?? panelId,
                stackIndex: stackIndex
            )
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

    private func makePanel(panelId: String) -> AgentFloatingPanel {
        let panel = AgentFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 52),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.panelId = panelId
        panel.stackController = self
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
        snapToDock: Bool = false,
        anchorStackBottom: CGFloat? = nil,
        anchorPanelIndex: Int? = nil,
        anchorY: CGFloat? = nil,
        display: Bool,
        animated: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        guard !orderedIds.isEmpty else {
            completion?()
            return
        }

        let entries = orderedIds.compactMap { panels[$0] }
        guard entries.count == orderedIds.count else {
            completion?()
            return
        }

        for entry in entries {
            _ = remeasurePanel(entry)
        }

        let sizes = panelSizes(for: entries)
        let collapsed = entries.count > 1 && !isStackExpanded
        let gap = snapGap * CGFloat(max(entries.count - 1, 0))
        let peekTotal = stackPeekStep * CGFloat(max(entries.count - 1, 0))
        let totalHeight: CGFloat
        if collapsed {
            totalHeight = sizes[0].height + peekTotal
        } else {
            totalHeight = sizes.map(\.height).reduce(0, +) + gap
        }

        let screen = resolvedLayoutScreen(for: entries.map(\.panel.frame))
        let visible = screen.visibleFrame

        let startBottomY: CGFloat
        if let anchorPanelIndex, let anchorY {
            if collapsed {
                startBottomY = anchorY - CGFloat(anchorPanelIndex) * stackPeekStep
            } else {
                var bottom = anchorY
                for i in 0..<anchorPanelIndex {
                    bottom -= snapGap + sizes[i].height
                }
                startBottomY = bottom
            }
        } else if let anchorStackBottom {
            startBottomY = anchorStackBottom
        } else if snapToDock || groupStackBottomY == nil {
            startBottomY = dockBaselineY(in: visible)
        } else {
            startBottomY = groupStackBottomY ?? dockBaselineY(in: visible)
        }

        let clampedStartBottomY = min(
            max(startBottomY, visible.minY),
            max(visible.minY, visible.maxY - totalHeight)
        )
        groupStackBottomY = clampedStartBottomY

        FloatingPanelPlacement.rememberScreen(screen.placementIdentifier)

        let frames = computePanelFrames(
            entries: entries,
            sizes: sizes,
            collapsed: collapsed,
            clampedStartBottomY: clampedStartBottomY,
            visible: visible
        )

        applyPanelFrames(
            frames,
            entries: entries,
            collapsed: collapsed,
            display: display,
            animated: animated && entries.count > 1,
            completion: completion
        )
    }

    private func computePanelFrames(
        entries: [AgentPanelWindow],
        sizes: [NSSize],
        collapsed: Bool,
        clampedStartBottomY: CGFloat,
        visible: NSRect
    ) -> [(AgentPanelWindow, NSRect)] {
        if collapsed {
            return entries.enumerated().map { index, entry in
                let size = sizes[index]
                let peekOffset = CGFloat(index) * stackPeekStep
                let x = centeredX(in: visible, width: size.width)
                let frame = NSRect(
                    x: x,
                    y: clampedStartBottomY + peekOffset,
                    width: size.width,
                    height: size.height
                )
                return (entry, frame)
            }
        }

        var bottomY = clampedStartBottomY
        return entries.enumerated().map { index, entry in
            let size = sizes[index]
            let x = centeredX(in: visible, width: size.width)
            let frame = NSRect(x: x, y: bottomY, width: size.width, height: size.height)
            bottomY += size.height + snapGap
            return (entry, frame)
        }
    }

    private func applyPanelFrames(
        _ frames: [(AgentPanelWindow, NSRect)],
        entries: [AgentPanelWindow],
        collapsed: Bool,
        display: Bool,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        isApplyingLayout = true

        let finalize: () -> Void = { [weak self] in
            guard let self else { return }
            if collapsed {
                self.updateCollapsedZOrder(entries)
            }
            self.isApplyingLayout = false
            self.isStackAnimating = false
            completion?()
        }

        guard animated else {
            for (entry, frame) in frames {
                entry.panel.setFrame(frame, display: display)
            }
            if collapsed {
                updateCollapsedZOrder(entries)
            }
            isApplyingLayout = false
            completion?()
            return
        }

        isStackAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = stackAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            for (entry, frame) in frames {
                entry.panel.animator().setFrame(frame, display: display)
            }
        }, completionHandler: {
            Task { @MainActor in
                finalize()
            }
        })
    }

    private func updateCollapsedZOrder(_ entries: [AgentPanelWindow]) {
        for index in entries.indices.reversed() {
            entries[index].panel.orderFrontRegardless()
        }
    }

    /// Dock 可见区域上方、面板底边的 Y 坐标
    private func dockBaselineY(in visible: NSRect) -> CGFloat {
        visible.minY + dockTopMargin
    }

    /// 单面板在可见区域内水平居中时的左边缘 X
    private func centeredX(in visible: NSRect, width: CGFloat) -> CGFloat {
        min(max(visible.midX - width / 2, visible.minX), max(visible.minX, visible.maxX - width))
    }

    private func snapMovedFrame(_ frame: NSRect, movedIndex: Int, orderedIds: [String]) -> NSRect {
        let entries = orderedIds.compactMap { panels[$0] }
        guard movedIndex < entries.count else { return frame }

        let sizes = panelSizes(for: entries)
        let movedSize = sizes[movedIndex]
        let screen = screenContaining(point: frame.origin) ?? resolvedLayoutScreen(for: [frame])
        let visible = screen.visibleFrame
        var snapped = frame

        snapped.origin.x = centeredX(in: visible, width: movedSize.width)

        let dockY = dockBaselineY(in: visible)
        var groupBottom = snapped.origin.y
        for i in 0..<movedIndex {
            groupBottom -= snapGap + sizes[i].height
        }
        if abs(groupBottom - dockY) <= snapThreshold {
            var alignedY = dockY
            for i in 0..<movedIndex {
                alignedY += snapGap + sizes[i].height
            }
            snapped.origin.y = alignedY
        }

        guard entries.count > 1 else { return snapped }

        if movedIndex > 0 {
            let belowNeighbor = entries[movedIndex - 1].panel.frame
            let targetBottom = belowNeighbor.maxY + snapGap
            if abs(snapped.origin.y - targetBottom) <= snapThreshold {
                snapped.origin.y = targetBottom
            }
        }

        if movedIndex < entries.count - 1 {
            let aboveNeighbor = entries[movedIndex + 1].panel.frame
            let targetBottom = aboveNeighbor.minY - snapGap - movedSize.height
            if abs(snapped.origin.y - targetBottom) <= snapThreshold {
                snapped.origin.y = targetBottom
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
            anchorStackBottom: groupStackBottomY,
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
                anchorStackBottom: self.groupStackBottomY,
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
        guard let stackBottomY = groupStackBottomY else { return }
        let screen = screenContaining(point: frame.origin) ?? resolvedLayoutScreen(for: [frame])
        FloatingPanelPlacement.saveUserPlacement(
            screenId: screen.placementIdentifier,
            anchorLeft: 0,
            baselineY: stackBottomY
        )
    }

    private func expandedStackBounds() -> NSRect {
        let frames = lastOrderedIds.compactMap { panels[$0]?.panel.frame }
        guard var union = frames.first else { return .zero }
        for frame in frames.dropFirst() {
            union = union.union(frame)
        }
        return union
    }

    private func startCollapseMonitoring() {
        guard mouseMonitors.isEmpty else { return }

        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.scheduleCollapseCheck()
            }
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            mouseMonitors.append(global)
        }

        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor in
                self?.scheduleCollapseCheck()
            }
            return event
        }
        mouseMonitors.append(local)
    }

    private func stopCollapseMonitoring() {
        collapseDebounceTimer?.invalidate()
        collapseDebounceTimer = nil
        for monitor in mouseMonitors {
            NSEvent.removeMonitor(monitor)
        }
        mouseMonitors.removeAll()
    }

    private func scheduleCollapseCheck() {
        collapseDebounceTimer?.invalidate()
        collapseDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.checkCollapseIfMouseOutside()
            }
        }
    }

    private func checkCollapseIfMouseOutside() {
        guard isStackExpanded, panels.count > 1, !isStackAnimating else { return }
        let mouse = NSEvent.mouseLocation
        let bounds = expandedStackBounds().insetBy(dx: -16, dy: -16)
        guard !bounds.contains(mouse) else { return }
        collapseStack()
    }
}
