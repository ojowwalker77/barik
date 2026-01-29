import Foundation

struct MenuBarAutoHide {
    static func setAutoHide(_ enabled: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", "NSGlobalDomain", "_HIHideMenuBar", "-bool", enabled ? "true" : "false"]
        try? task.run()
        task.waitUntilExit()

        // Attempt refresh without logout
        let dock = Process()
        dock.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        dock.arguments = ["Dock"]
        try? dock.run()
    }
}
