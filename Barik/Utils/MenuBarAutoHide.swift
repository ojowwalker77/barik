import Foundation

struct MenuBarAutoHide {
    private static var lastState: Bool?

    static func setAutoHide(_ enabled: Bool) {
        // Skip if state unchanged
        if lastState == enabled {
            return
        }
        lastState = enabled

        let script = """
        tell application "System Events"
            tell dock preferences to set autohide menu bar to \(enabled)
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
