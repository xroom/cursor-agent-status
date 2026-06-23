import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingPanelRootView>?

    var isVisible: Bool { panel?.isVisible == true }

    func show(
        store: StatusStore,
        isAlwaysOnTop: Binding<Bool>,
        opacity: Binding<Double>,
        autoHideWhenIdle: Binding<Bool>
    ) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "Cursor Agent Status"
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            self.panel = panel
        }

        let root = FloatingPanelRootView(
            store: store,
            isAlwaysOnTop: isAlwaysOnTop,
            opacity: opacity,
            autoHideWhenIdle: autoHideWhenIdle,
            onClose: { [weak self] in self?.hide() }
        )

        if hostingView == nil {
            hostingView = NSHostingView(rootView: root)
            panel?.contentView = hostingView
        } else {
            hostingView?.rootView = root
        }

        applyWindowSettings(isAlwaysOnTop: isAlwaysOnTop.wrappedValue, opacity: opacity.wrappedValue)
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle(
        store: StatusStore,
        isAlwaysOnTop: Binding<Bool>,
        opacity: Binding<Double>,
        autoHideWhenIdle: Binding<Bool>
    ) {
        if isVisible {
            hide()
        } else {
            show(
                store: store,
                isAlwaysOnTop: isAlwaysOnTop,
                opacity: opacity,
                autoHideWhenIdle: autoHideWhenIdle
            )
        }
    }

    func applyWindowSettings(isAlwaysOnTop: Bool, opacity: Double) {
        panel?.level = isAlwaysOnTop ? .floating : .normal
        panel?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(opacity)
    }

    func updateAutoHide(store: StatusStore, autoHideWhenIdle: Bool) {
        guard autoHideWhenIdle else { return }
        if store.activeCount == 0 && store.pendingCount == 0 && store.recentCount == 0 {
            hide()
        }
    }
}

private struct FloatingPanelRootView: View {
    @Bindable var store: StatusStore
    @Binding var isAlwaysOnTop: Bool
    @Binding var opacity: Double
    @Binding var autoHideWhenIdle: Bool
    var onClose: () -> Void

    var body: some View {
        FloatingPanelView(
            store: store,
            isAlwaysOnTop: $isAlwaysOnTop,
            opacity: $opacity,
            autoHideWhenIdle: $autoHideWhenIdle,
            onClose: onClose
        )
        .onChange(of: isAlwaysOnTop) { _, value in
            NotificationCenter.default.post(
                name: .floatingPanelSettingsChanged,
                object: nil,
                userInfo: ["alwaysOnTop": value, "opacity": opacity]
            )
        }
        .onChange(of: opacity) { _, value in
            NotificationCenter.default.post(
                name: .floatingPanelSettingsChanged,
                object: nil,
                userInfo: ["alwaysOnTop": isAlwaysOnTop, "opacity": value]
            )
        }
    }
}

extension Notification.Name {
    static let floatingPanelSettingsChanged = Notification.Name("floatingPanelSettingsChanged")
}
