import Foundation

/// Configures tiling window managers (AeroSpace, Yabai) to respect Barik's space
class TilingWMConfigurator {

    static func configureOnLaunch(barHeight: Int) {
        configureAeroSpace(barHeight: barHeight)
        configureYabai(barHeight: barHeight)
    }

    // MARK: - AeroSpace

    private static func configureAeroSpace(barHeight: Int) {
        let configPath = NSString(string: "~/.aerospace.toml").expandingTildeInPath

        guard FileManager.default.fileExists(atPath: configPath) else {
            print("[Barik] AeroSpace config not found at \(configPath)")
            return
        }

        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            print("[Barik] Could not read AeroSpace config")
            return
        }

        // Check if already configured with per-monitor settings for Barik
        if isAlreadyConfiguredForBarik(content: content, barHeight: barHeight) {
            print("[Barik] AeroSpace already configured with per-monitor gaps for Barik")
            return
        }

        // Update the config with per-monitor gaps
        // main (notched) display keeps original value, secondary (external) gets barHeight
        if let updated = updateAeroSpaceOuterTop(in: content, to: barHeight) {
            do {
                try updated.write(toFile: configPath, atomically: true, encoding: .utf8)
                print("[Barik] Updated AeroSpace with per-monitor outer.top (secondary = \(barHeight))")

                // Reload AeroSpace config
                reloadAeroSpace()
            } catch {
                print("[Barik] Failed to write AeroSpace config: \(error)")
            }
        }
    }

    private static func isAlreadyConfiguredForBarik(content: String, barHeight: Int) -> Bool {
        // Check if outer.top has per-monitor config with Built-in pattern and barHeight as default
        // Pattern: outer.top = [{ monitor."^Built-in.*" = 10 }, 55]
        let pattern = "outer\\.top\\s*=\\s*\\[.*Built-in.*,\\s*\(barHeight)\\s*\\]"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) != nil {
            return true
        }
        return false
    }

    private static func updateAeroSpaceOuterTop(in content: String, to value: Int) -> String? {
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

            if inGapsSection && trimmed.hasPrefix("outer.top") {
                let indent = String(line.prefix(while: { $0.isWhitespace }))
                let defaultGap = 10

                // Per-monitor config using monitor name regex:
                // - "Built-in.*" matches MacBook display (has notch, macOS reserves space)
                // - Default (everything else) = barHeight for external monitors
                lines[index] = "\(indent)outer.top = [{ monitor.\"^Built-in.*\" = \(defaultGap) }, \(value)]"
                return lines.joined(separator: "\n")
            }
        }

        // No outer.top found, add to [gaps] section
        var gapsIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[gaps]") }

        if gapsIndex == nil {
            // Add [gaps] section at the end
            lines.append("")
            lines.append("[gaps]")
            gapsIndex = lines.count - 1
        }

        // Insert after [gaps] line
        // Use regex to match Built-in display (MacBook with notch)
        if let idx = gapsIndex {
            lines.insert("outer.top = [{ monitor.\"^Built-in.*\" = 10 }, \(value)]", at: idx + 1)
        }

        return lines.joined(separator: "\n")
    }

    private static func extractMainValue(from line: String) -> Int? {
        // Extract value from: outer.top = [{ monitor.main = 16 }, ...]
        let pattern = "monitor\\.main\\s*=\\s*(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return Int(line[range])
    }

    private static func extractSimpleValue(from line: String) -> Int? {
        // Extract value from: outer.top = 10
        let parts = line.components(separatedBy: "=")
        if parts.count >= 2 {
            let valueStr = parts[1].trimmingCharacters(in: .whitespaces)
            return Int(valueStr)
        }
        return nil
    }

    private static func reloadAeroSpace() {
        let aerospacePathBrew = "/opt/homebrew/bin/aerospace"
        let aerospacePathLocal = "/usr/local/bin/aerospace"

        let path: String
        if FileManager.default.fileExists(atPath: aerospacePathBrew) {
            path = aerospacePathBrew
        } else if FileManager.default.fileExists(atPath: aerospacePathLocal) {
            path = aerospacePathLocal
        } else {
            print("[Barik] AeroSpace binary not found")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["reload-config"]

        do {
            try task.run()
            task.waitUntilExit()
            print("[Barik] AeroSpace config reloaded")
        } catch {
            print("[Barik] Failed to reload AeroSpace: \(error)")
        }
    }

    // MARK: - Yabai

    private static func configureYabai(barHeight: Int) {
        let yabaiPathBrew = "/opt/homebrew/bin/yabai"
        let yabaiPathLocal = "/usr/local/bin/yabai"

        let path: String
        if FileManager.default.fileExists(atPath: yabaiPathBrew) {
            path = yabaiPathBrew
        } else if FileManager.default.fileExists(atPath: yabaiPathLocal) {
            path = yabaiPathLocal
        } else {
            print("[Barik] Yabai not found")
            return
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
                print("[Barik] Yabai is not running")
                return
            }
        } catch {
            print("[Barik] Failed to check Yabai status: \(error)")
            return
        }

        // Configure external_bar for all displays
        // Format: yabai -m config external_bar all:TOP_PADDING:BOTTOM_PADDING
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["-m", "config", "external_bar", "all:\(barHeight):0"]

        do {
            try task.run()
            task.waitUntilExit()
            print("[Barik] Configured Yabai external_bar to \(barHeight)")
        } catch {
            print("[Barik] Failed to configure Yabai: \(error)")
        }
    }
}
