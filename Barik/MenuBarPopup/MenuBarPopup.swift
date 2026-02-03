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
    private static let minPopupSize = CGSize(width: 160, height: 120)

    static func show<Content: View>(
        rect: CGRect, id: String, @ViewBuilder content: @escaping () -> Content
    ) {
        debugLog("[DEBUG] MenuBarPopup.show called - id: \(id), rect: \(rect)")

        // Find which screen the widget rect is on
        let targetScreen = screenForRect(rect) ?? NSScreen.main

        guard let screen = targetScreen else {
            debugLog("[DEBUG] No screen found!")
            return
        }
        let displayID = screen.displayID
        debugLog("[DEBUG] Screen: \(screen.frame), displayID: \(displayID)")

        guard let panel = panels[displayID] else {
            debugLog("[DEBUG] No panel for displayID: \(displayID), available: \(panels.keys)")
            return
        }
        debugLog("[DEBUG] Panel found, frame: \(panel.frame), level: \(panel.level.rawValue)")

        let position = ConfigManager.shared.config.experimental.foreground.position
        debugLog("[DEBUG] Position: \(position)")

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

        var lastMeasuredSize: CGSize = .zero

        let popupView = AnyView(
            MenuBarPopupView(position: position, onSizeChange: { newSize in
                guard abs(newSize.width - lastMeasuredSize.width) > 1
                        || abs(newSize.height - lastMeasuredSize.height) > 1 else {
                    return
                }
                lastMeasuredSize = newSize
                applyPopupFrame(
                    panel: panel,
                    screen: screen,
                    rect: rect,
                    size: newSize,
                    position: position
                )
            }) {
                content()
            }
        )

        let hostedView = NSHostingView(rootView: popupView.fixedSize())
        let fittingSize = hostedView.fittingSize
        lastMeasuredSize = fittingSize
        applyPopupFrame(
            panel: panel,
            screen: screen,
            rect: rect,
            size: fittingSize,
            position: position
        )

        if panel.isKeyWindow {
            NotificationCenter.default.post(
                name: .willChangeContent, object: nil)
            let baseDuration =
                Double(Constants.menuBarPopupAnimationDurationInMilliseconds)
                / 1000.0
            let duration = isContentChange ? baseDuration / 2 : baseDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                panel.contentView = NSHostingView(rootView: popupView.id(UUID()))
                panel.makeKeyAndOrderFront(nil)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .willShowWindow, object: nil)
                }
            }
        } else {
            debugLog("[DEBUG] Showing popup panel (not key)")
            panel.contentView = NSHostingView(rootView: popupView)
            panel.makeKeyAndOrderFront(nil)
            debugLog("[DEBUG] makeKeyAndOrderFront called, isVisible: \(panel.isVisible), isKey: \(panel.isKeyWindow)")
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

            if let existingPanel = panels[displayID] {
                // Just update the level, frame is set in show()
                existingPanel.level = NSWindow.Level(
                    rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
                continue
            }

            // Create with minimal frame - actual position set in show()
            let newPanel = HidingPanel(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                styleMask: [.nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            newPanel.level = NSWindow.Level(
                rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
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

    private static func screenForRect(_ rect: CGRect) -> NSScreen? {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) {
            return screen
        }

        // Fallback: try offsetting by each screen origin (rect might be in window coords)
        for screen in NSScreen.screens {
            let adjusted = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
            if screen.frame.contains(CGPoint(x: adjusted.midX, y: adjusted.midY)) {
                return screen
            }
        }

        return nil
    }

    private static func applyPopupFrame(
        panel: NSPanel,
        screen: NSScreen,
        rect: CGRect,
        size: CGSize,
        position: BarPosition
    ) {
        let visibleFrame = screen.visibleFrame
        let normalizedRect = normalizeWidgetRect(rect, screen: screen, position: position)
        let popupSize = clampedPopupSize(
            size: size,
            visibleFrame: visibleFrame,
            minSize: minPopupSize
        )

        // Panel X: centered on widget, clamped to screen visible frame
        let desiredX = normalizedRect.midX - popupSize.width / 2
        let panelX = clamp(
            desiredX,
            min: visibleFrame.minX + 10,
            max: visibleFrame.maxX - popupSize.width - 10
        )

        // rect is already in global screen coords (origin bottom-left)
        let widgetTopMacOS = normalizedRect.maxY
        let widgetBottomMacOS = normalizedRect.minY

        let padding: CGFloat = 5
        let spaceAbove = visibleFrame.maxY - widgetTopMacOS
        let spaceBelow = widgetBottomMacOS - visibleFrame.minY

        let prefersBelow = position == .top
        let needsFlip = prefersBelow
            ? spaceBelow < popupSize.height + padding
            : spaceAbove < popupSize.height + padding

        let showBelow = prefersBelow != needsFlip

        // Panel Y: above widget for bottom bar, below widget for top bar
        let desiredY: CGFloat = showBelow
            ? widgetBottomMacOS - popupSize.height - padding
            : widgetTopMacOS + padding
        let panelY = clamp(
            desiredY,
            min: visibleFrame.minY + 10,
            max: visibleFrame.maxY - popupSize.height - 10
        )
        debugLog("[DEBUG] widgetTopMacOS: \(widgetTopMacOS), widgetBottomMacOS: \(widgetBottomMacOS)")

        let panelFrame = CGRect(origin: CGPoint(x: panelX, y: panelY), size: popupSize)
        panel.setFrame(panelFrame, display: false)
        debugLog("[DEBUG] Panel frame set to: \(panelFrame)")
    }

    private static func clampedPopupSize(
        size: CGSize,
        visibleFrame: CGRect,
        minSize: CGSize
    ) -> CGSize {
        let maxWidth = max(minSize.width, visibleFrame.width - 20)
        let maxHeight = max(minSize.height, visibleFrame.height - 20)
        let width = min(max(size.width, minSize.width), maxWidth)
        let height = min(max(size.height, minSize.height), maxHeight)
        return CGSize(width: width, height: height)
    }

    private static func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }

    private static func normalizeWidgetRect(
        _ rect: CGRect,
        screen: NSScreen,
        position: BarPosition
    ) -> CGRect {
        let visibleFrame = screen.visibleFrame

        let likelyFlippedTopOrigin = position == .bottom
            ? rect.minY > visibleFrame.midY
            : rect.maxY < visibleFrame.midY

        guard likelyFlippedTopOrigin else { return rect }

        let screenMaxY = screen.frame.maxY
        let convertedMinY = screenMaxY - rect.maxY
        let convertedMaxY = screenMaxY - rect.minY

        return CGRect(
            x: rect.origin.x,
            y: convertedMinY,
            width: rect.width,
            height: convertedMaxY - convertedMinY
        )
    }

    #if DEBUG
    private static func debugLog(_ message: @autoclosure () -> String) {
        print(message())
    }
    #else
    private static func debugLog(_ message: @autoclosure () -> String) {}
    #endif
}
