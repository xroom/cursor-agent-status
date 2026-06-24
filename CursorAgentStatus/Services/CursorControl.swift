import AppKit
import CoreGraphics

enum CursorControl {
    private static let cursorBundleID = "com.todesktop.230313mzl4w4u92"

    /// 激活 Cursor 并发送 ⌘⇧⌫（Cancel generation）
    static func cancelGeneration() {
        activateCursor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            postCancelShortcut()
        }
    }

    private static func activateCursor() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: cursorBundleID).first {
            app.activate(options: [.activateIgnoringOtherApps])
        } else {
            NSWorkspace.shared.launchApplication("Cursor")
        }
    }

    private static func postCancelShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode: CGKeyCode = 0x33

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = [.maskCommand, .maskShift]
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = [.maskCommand, .maskShift]
        keyUp?.post(tap: .cghidEventTap)
    }
}
