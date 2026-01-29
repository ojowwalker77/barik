import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var backgroundPanels: [CGDirectDisplayID: NSPanel] = [:]
    private var menuBarPanels: [CGDirectDisplayID: NSPanel] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let error = ConfigManager.shared.initError {
            showFatalConfigError(message: error)
            return
        }
        
        // Show "What's New" banner if the app version is outdated
        if !VersionChecker.isLatestVersion() {
            VersionChecker.updateVersionFile()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(
                    name: Notification.Name("ShowWhatsNewBanner"), object: nil)
            }
        }
        
        // Configure tiling WMs to respect Barik's space
        let barHeight = Int(ConfigManager.shared.config.experimental.foreground.resolveHeight())
        TilingWMConfigurator.configureOnLaunch(barHeight: barHeight)

        MenuBarPopup.setup()
        setupPanels()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        setupPanels()
    }

    /// Configures and displays the background and menu bar panels on all screens.
    private func setupPanels() {
        let screens = NSScreen.screens
        var activeDisplayIDs = Set<CGDirectDisplayID>()

        for screen in screens {
            let displayID = screen.displayID
            activeDisplayIDs.insert(displayID)
            let screenFrame = screen.frame

            setupPanel(
                in: &backgroundPanels,
                for: displayID,
                frame: screenFrame,
                level: Int(CGWindowLevelForKey(.desktopWindow)),
                hostingRootView: AnyView(BackgroundView()))
            setupPanel(
                in: &menuBarPanels,
                for: displayID,
                frame: screenFrame,
                level: Int(CGWindowLevelForKey(.backstopMenu)),
                hostingRootView: AnyView(MenuBarView(monitorName: screen.localizedName)))
        }

        // Remove panels for disconnected screens
        for displayID in backgroundPanels.keys where !activeDisplayIDs.contains(displayID) {
            backgroundPanels[displayID]?.orderOut(nil)
            backgroundPanels.removeValue(forKey: displayID)
        }
        for displayID in menuBarPanels.keys where !activeDisplayIDs.contains(displayID) {
            menuBarPanels[displayID]?.orderOut(nil)
            menuBarPanels.removeValue(forKey: displayID)
        }

        MenuBarPopup.setupAllScreens()
    }

    /// Sets up an NSPanel with the provided parameters for a specific display.
    private func setupPanel(
        in panels: inout [CGDirectDisplayID: NSPanel],
        for displayID: CGDirectDisplayID,
        frame: CGRect,
        level: Int,
        hostingRootView: AnyView
    ) {
        if let existingPanel = panels[displayID] {
            existingPanel.setFrame(frame, display: true)
            return
        }

        let newPanel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false)
        newPanel.level = NSWindow.Level(rawValue: level)
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        newPanel.contentView = NSHostingView(rootView: hostingRootView)
        newPanel.setFrame(frame, display: true)
        newPanel.orderFront(nil)
        panels[displayID] = newPanel
    }
    
    private func showFatalConfigError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Configuration Error"
        alert.informativeText = "\(message)\n\nPlease double check ~/.barik-config.toml and try again."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
