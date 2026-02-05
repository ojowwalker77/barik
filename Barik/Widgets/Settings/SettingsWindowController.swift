import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var isClosing = false

    private init() {}

    func showSettings() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Start customization mode
        let engine = WidgetGridEngine.shared
        engine.startCustomizing()

        let customizationView = ToolbarCustomizationSheet()
        let hostingView = NSHostingView(rootView: customizationView)

        let windowWidth: CGFloat = 380
        let windowHeight: CGFloat = 460

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Customize Toolbar"
        newWindow.contentView = hostingView
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = WindowDelegate.shared

        // Position window near bar, centered horizontally
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let position = ConfigManager.shared.config.foreground.position
            let barHeight = ConfigManager.shared.config.foreground.resolveHeight()

            let x = (screenFrame.width - windowWidth) / 2
            let y: CGFloat

            if position == .top {
                // Below the bar at top
                let menuBarHeight = screenFrame.height - visibleFrame.height - visibleFrame.origin.y
                let topOffset = menuBarHeight + barHeight + 10
                y = screenFrame.height - topOffset - windowHeight
            } else {
                // Above the bar at bottom
                y = barHeight + 10
            }

            newWindow.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            newWindow.center()
        }

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }

    func closeWindow() {
        guard !isClosing, let win = window else { return }
        isClosing = true
        win.orderOut(nil)  // Hide immediately, no close events
        window = nil
        WidgetGridEngine.shared.isCustomizing = false
        isClosing = false
    }

    /// Called from WindowDelegate when window closes externally
    func windowDidClose() {
        window = nil
    }
}

// Window delegate to handle close events
private class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    func windowWillClose(_ notification: Notification) {
        let engine = WidgetGridEngine.shared
        if engine.hasUnsavedChanges {
            engine.cancelCustomizing()
        }
        engine.isCustomizing = false
        // Don't call closeWindow() - we're already in window close
        // Just clear the reference to avoid stale window pointer
        SettingsWindowController.shared.windowDidClose()
    }
}
