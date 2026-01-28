import SwiftUI

private var panels: [CGDirectDisplayID: NSPanel] = [:]

class HidingPanel: NSPanel, NSWindowDelegate {
    var hideTimer: Timer?

    override var canBecomeKey: Bool {
        return true
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing bufferingType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect, styleMask: style, backing: bufferingType,
            defer: flag)
        self.delegate = self
    }

    func windowDidResignKey(_ notification: Notification) {
        NotificationCenter.default.post(name: .willHideWindow, object: nil)
        hideTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(
                Constants.menuBarPopupAnimationDurationInMilliseconds) / 1000.0,
            repeats: false
        ) { [weak self] _ in
            self?.orderOut(nil)
        }
    }
}

class MenuBarPopup {
    static var lastContentIdentifier: String? = nil
    static var lastDisplayID: CGDirectDisplayID? = nil

    static func show<Content: View>(
        rect: CGRect, id: String, @ViewBuilder content: @escaping () -> Content
    ) {
        // Find which screen the widget rect is on
        let targetScreen = NSScreen.screens.first { screen in
            screen.frame.contains(CGPoint(x: rect.midX, y: rect.midY))
        } ?? NSScreen.main

        guard let screen = targetScreen else { return }
        let displayID = screen.displayID
        guard let panel = panels[displayID] else { return }

        // Calculate position relative to screen origin
        let relativeX = rect.midX - screen.frame.origin.x

        // Hide other screen popups
        for (otherID, otherPanel) in panels where otherID != displayID {
            if otherPanel.isKeyWindow {
                otherPanel.orderOut(nil)
            }
        }

        if panel.isKeyWindow, lastContentIdentifier == id, lastDisplayID == displayID {
            NotificationCenter.default.post(name: .willHideWindow, object: nil)
            let duration =
                Double(Constants.menuBarPopupAnimationDurationInMilliseconds)
                / 1000.0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                panel.orderOut(nil)
                lastContentIdentifier = nil
                lastDisplayID = nil
            }
            return
        }

        let isContentChange =
            panel.isKeyWindow
            && (lastContentIdentifier != nil && lastContentIdentifier != id)
        lastContentIdentifier = id
        lastDisplayID = displayID

        if let hidingPanel = panel as? HidingPanel {
            hidingPanel.hideTimer?.invalidate()
            hidingPanel.hideTimer = nil
        }

        let screenBounds = ScreenBounds(width: screen.frame.width, originX: screen.frame.origin.x)

        if panel.isKeyWindow {
            NotificationCenter.default.post(
                name: .willChangeContent, object: nil)
            let baseDuration =
                Double(Constants.menuBarPopupAnimationDurationInMilliseconds)
                / 1000.0
            let duration = isContentChange ? baseDuration / 2 : baseDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                panel.contentView = NSHostingView(
                    rootView:
                        ZStack {
                            MenuBarPopupView(screenBounds: screenBounds) {
                                content()
                            }
                            .position(x: relativeX)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(UUID())
                )
                panel.makeKeyAndOrderFront(nil)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .willShowWindow, object: nil)
                }
            }
        } else {
            panel.contentView = NSHostingView(
                rootView:
                    ZStack {
                        MenuBarPopupView(screenBounds: screenBounds) {
                            content()
                        }
                        .position(x: relativeX)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
            panel.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .willShowWindow, object: nil)
            }
        }
    }

    static func setup() {
        setupAllScreens()
    }

    static func setupAllScreens() {
        let screens = NSScreen.screens
        var activeDisplayIDs = Set<CGDirectDisplayID>()

        for screen in screens {
            let displayID = screen.displayID
            activeDisplayIDs.insert(displayID)

            if panels[displayID] != nil {
                // Update existing panel frame
                let panelFrame = NSRect(
                    x: screen.frame.origin.x,
                    y: screen.frame.origin.y,
                    width: screen.frame.width,
                    height: screen.visibleFrame.height
                )
                panels[displayID]?.setFrame(panelFrame, display: true)
                continue
            }

            let panelFrame = NSRect(
                x: screen.frame.origin.x,
                y: screen.frame.origin.y,
                width: screen.frame.width,
                height: screen.visibleFrame.height
            )

            let newPanel = HidingPanel(
                contentRect: panelFrame,
                styleMask: [.nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            newPanel.level = NSWindow.Level(
                rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = false
            newPanel.collectionBehavior = [.canJoinAllSpaces]

            panels[displayID] = newPanel
        }

        // Remove panels for disconnected screens
        for displayID in panels.keys where !activeDisplayIDs.contains(displayID) {
            panels[displayID]?.orderOut(nil)
            panels.removeValue(forKey: displayID)
        }
    }
}

struct ScreenBounds {
    let width: CGFloat
    let originX: CGFloat
}
