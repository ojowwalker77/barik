import Foundation

/// Configures tiling window managers (AeroSpace, Yabai) to respect Barik's space
class TilingWMConfigurator {
    private static let lock = NSLock()
    private struct ConfigurationRequest: Equatable {
        let barSize: Int
        let position: BarPosition
    }

    private static var lastApplied: ConfigurationRequest?
    private static var pendingRequest: ConfigurationRequest?

    static func configureOnLaunch(barSize: Int, position: BarPosition) {
        let request = ConfigurationRequest(barSize: barSize, position: position)
        guard beginConfigurationIfNeeded(request) else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let aerospaceSucceeded = configureAeroSpace(barSize: barSize, position: position)
            let yabaiSucceeded = configureYabai(barSize: barSize, position: position)
            finishConfiguration(request, succeeded: aerospaceSucceeded && yabaiSucceeded)
        }
    }

    static func beginConfigurationIfNeeded(_ request: (barSize: Int, position: BarPosition)) -> Bool {
        beginConfigurationIfNeeded(ConfigurationRequest(barSize: request.barSize, position: request.position))
    }

    static func finishConfiguration(_ request: (barSize: Int, position: BarPosition), succeeded: Bool) {
        finishConfiguration(ConfigurationRequest(barSize: request.barSize, position: request.position), succeeded: succeeded)
    }

    static func resetConfigurationState() {
        lock.lock()
        defer { lock.unlock() }
        lastApplied = nil
        pendingRequest = nil
    }

    private static func beginConfigurationIfNeeded(_ request: ConfigurationRequest) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if lastApplied == request || pendingRequest == request {
            return false
        }
        pendingRequest = request
        return true
    }

    private static func finishConfiguration(_ request: ConfigurationRequest, succeeded: Bool) {
        lock.lock()
        defer { lock.unlock() }

        if pendingRequest == request {
            pendingRequest = nil
        }
        if succeeded {
            lastApplied = request
        }
    }

    // MARK: - AeroSpace

    private static func configureAeroSpace(barSize: Int, position: BarPosition) -> Bool {
        let configPath = NSString(string: "~/.aerospace.toml").expandingTildeInPath

        guard FileManager.default.fileExists(atPath: configPath) else { return true }
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            AppDiagnostics.shared.post(id: "wm-aerospace", kind: .wm, title: "AeroSpace Config Error", message: "Unable to read ~/.aerospace.toml.")
            return false
        }

        let updated = applyingAeroSpaceGapEdits(to: content, barSize: barSize, position: position)

        do {
            try updated.write(toFile: configPath, atomically: true, encoding: .utf8)
            guard reloadAeroSpace() else { return false }
            AppDiagnostics.shared.clear(id: "wm-aerospace")
            return true
        } catch {
            AppDiagnostics.shared.post(id: "wm-aerospace", kind: .wm, title: "AeroSpace Config Error", message: error.localizedDescription)
            return false
        }
    }

    private static func aerospaceGapKey(for position: BarPosition) -> String {
        switch position {
        case .top: return "outer.top"
        case .bottom: return "outer.bottom"
        }
    }

    static func applyingAeroSpaceGapEdits(to content: String, barSize: Int, position: BarPosition) -> String {
        let allPositions: [BarPosition] = [.top, .bottom]
        let defaultGap = 10
        var updated = content

        for pos in allPositions {
            let gapKey = aerospaceGapKey(for: pos)
            let value = (pos == position) ? barSize : defaultGap
            updated = setAeroSpaceGap(in: updated, gapKey: gapKey, value: value, position: pos)
        }

        updated = resetAeroSpaceGap(in: updated, gapKey: "outer.left", value: defaultGap)
        updated = resetAeroSpaceGap(in: updated, gapKey: "outer.right", value: defaultGap)
        return updated
    }

    /// Sets a single AeroSpace gap in the config content.
    /// For .top position: uses per-monitor format to handle MacBook notch
    /// For others: uses simple value format
    private static func setAeroSpaceGap(in content: String, gapKey: String, value: Int, position: BarPosition) -> String {
        var lines = content.components(separatedBy: .newlines)
        var inGapsSection = false
        var gapsSectionEndIndex: Int?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[gaps]") {
                inGapsSection = true
                gapsSectionEndIndex = index
                continue
            }

            if inGapsSection && trimmed.hasPrefix("[") && !trimmed.hasPrefix("[gaps") {
                inGapsSection = false
                continue
            }

            if inGapsSection {
                gapsSectionEndIndex = index

                if trimmed.hasPrefix(gapKey) {
                    let indent = String(line.prefix(while: { $0.isWhitespace }))
                    lines[index] = formatAeroSpaceGapLine(indent: indent, gapKey: gapKey, value: value, position: position)
                    return lines.joined(separator: "\n")
                }
            }
        }

        // Gap key not found - add to [gaps] section
        var gapsIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[gaps]") }

        if gapsIndex == nil {
            lines.append("")
            lines.append("[gaps]")
            gapsIndex = lines.count - 1
        }

        // Insert after last line in [gaps] section, or right after [gaps] header
        let insertIndex = (gapsSectionEndIndex ?? gapsIndex!) + 1
        lines.insert(formatAeroSpaceGapLine(indent: "", gapKey: gapKey, value: value, position: position), at: insertIndex)

        return lines.joined(separator: "\n")
    }

    private static func formatAeroSpaceGapLine(indent: String, gapKey: String, value: Int, position: BarPosition) -> String {
        // Per-monitor format for .top to handle MacBook notch (Built-in display uses default, externals use value)
        if position == .top {
            return "\(indent)\(gapKey) = [{ monitor.\"^Built-in.*\" = 10 }, \(value)]"
        } else {
            return "\(indent)\(gapKey) = \(value)"
        }
    }

    /// Resets a gap to a simple value (used for cleaning up old left/right gaps)
    private static func resetAeroSpaceGap(in content: String, gapKey: String, value: Int) -> String {
        var lines = content.components(separatedBy: .newlines)
        var inGapsSection = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[gaps]") {
                inGapsSection = true
                continue
            }

            if inGapsSection && trimmed.hasPrefix("[") && !trimmed.hasPrefix("[gaps") {
                inGapsSection = false
                continue
            }

            if inGapsSection && trimmed.hasPrefix(gapKey) {
                let indent = String(line.prefix(while: { $0.isWhitespace }))
                lines[index] = "\(indent)\(gapKey) = \(value)"
                return lines.joined(separator: "\n")
            }
        }

        // Gap not found, nothing to reset
        return content
    }

    private static func reloadAeroSpace() -> Bool {
        let aerospacePathBrew = "/opt/homebrew/bin/aerospace"
        let aerospacePathLocal = "/usr/local/bin/aerospace"

        let path: String
        if FileManager.default.fileExists(atPath: aerospacePathBrew) {
            path = aerospacePathBrew
        } else if FileManager.default.fileExists(atPath: aerospacePathLocal) {
            path = aerospacePathLocal
        } else {
            return true
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["reload-config"]

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                AppDiagnostics.shared.post(id: "wm-aerospace", kind: .wm, title: "AeroSpace Reload Failed", message: "AeroSpace rejected the updated configuration.")
                return false
            }
            return true
        } catch {
            AppDiagnostics.shared.post(id: "wm-aerospace", kind: .wm, title: "AeroSpace Reload Failed", message: error.localizedDescription)
            return false
        }
    }

    // MARK: - Yabai

    private static func configureYabai(barSize: Int, position: BarPosition) -> Bool {
        let path = ConfigManager.shared.config.yabai.path
        guard FileManager.default.fileExists(atPath: path) else {
            return true
        }

        // Check if yabai is running
        let checkTask = Process()
        checkTask.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        checkTask.arguments = ["-x", "yabai"]

        let pipe = Pipe()
        checkTask.standardOutput = pipe

        do {
            try checkTask.run()
            checkTask.waitUntilExit()

            if checkTask.terminationStatus != 0 {
                return true
            }
        } catch {
            return true
        }

        // Configure based on position
        switch position {
        case .top:
            return configureYabaiExternalBar(path: path, topPadding: barSize, bottomPadding: 0)
        case .bottom:
            return configureYabaiExternalBar(path: path, topPadding: 0, bottomPadding: barSize)
        }
    }

    private static func configureYabaiExternalBar(path: String, topPadding: Int, bottomPadding: Int) -> Bool {
        // Format: yabai -m config external_bar all:TOP_PADDING:BOTTOM_PADDING
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["-m", "config", "external_bar", "all:\(topPadding):\(bottomPadding)"]

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                AppDiagnostics.shared.post(id: "wm-yabai", kind: .wm, title: "Yabai Config Failed", message: "Unable to update yabai external_bar.")
                return false
            } else {
                AppDiagnostics.shared.clear(id: "wm-yabai")
                return true
            }
        } catch {
            AppDiagnostics.shared.post(id: "wm-yabai", kind: .wm, title: "Yabai Config Failed", message: error.localizedDescription)
            return false
        }
    }

}
