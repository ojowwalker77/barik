import Foundation
import SwiftUI
import TOMLDecoder

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published private(set) var config = Config()
    @Published private(set) var initError: String?

    /// The new typed config (available via ConfigStore.shared)
    private(set) var typedConfig: BarikConfig = .init()

    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var configFilePath: String?

    var configFileURL: URL? {
        guard let path = configFilePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var configFilePathForDisplay: String {
        configFilePath ?? "~/.config/barik/config.toml"
    }

    private init() {
        // Run migration and initialize ConfigStore
        let result = ConfigMigration.migrateIfNeeded()
        typedConfig = result.config
        ConfigStore.shared.initialize(with: result.config)

        // Observe ConfigStore changes to keep legacy Config in sync
        ConfigStore.shared.onChange { [weak self] newConfig in
            self?.typedConfig = newConfig
        }

        loadOrCreateConfigIfNeeded()
    }

    private func loadOrCreateConfigIfNeeded() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let path1 = "\(homePath)/.barik-config.toml"
        let path2 = "\(homePath)/.config/barik/config.toml"
        var chosenPath: String?

        if FileManager.default.fileExists(atPath: path1) {
            chosenPath = path1
        } else if FileManager.default.fileExists(atPath: path2) {
            chosenPath = path2
        } else {
            do {
                try createDefaultConfig(at: path1)
                chosenPath = path1
            } catch {
                initError = "Error creating default config: \(error.localizedDescription)"
                print("Error when creating default config:", error)
                return
            }
        }

        if let path = chosenPath {
            configFilePath = path
            parseConfigFile(at: path)
            startWatchingFile(at: path)
        }
    }

    private func parseConfigFile(at path: String) {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let decoder = TOMLDecoder()
            let rootToml = try decoder.decode(RootToml.self, from: content)
            let newConfig = Config(rootToml: rootToml)
            let position = newConfig.experimental.foreground.position
            MenuBarAutoHide.setAutoHide(position == .top)

            if Thread.isMainThread {
                self.config = newConfig
                NotificationCenter.default.post(name: Notification.Name("ConfigDidChange"), object: nil)
            } else {
                DispatchQueue.main.async {
                    self.config = newConfig
                    NotificationCenter.default.post(name: Notification.Name("ConfigDidChange"), object: nil)
                }
            }

            // Migrate config if needed (add missing default widgets)
            migrateConfigIfNeeded(config: newConfig, path: path)
        } catch {
            let errorMessage = "Error parsing TOML file: \(error.localizedDescription)"
            print("Error when parsing TOML file:", error)
            if Thread.isMainThread {
                self.initError = errorMessage
            } else {
                DispatchQueue.main.async {
                    self.initError = errorMessage
                }
            }
        }
    }

    private func migrateConfigIfNeeded(config: Config, path: String) {
        let displayedWidgets = config.rootToml.widgets.displayed.map { $0.id }

        // Add default.bluetooth if missing
        if !displayedWidgets.contains("default.bluetooth") {
            addWidgetToDisplayed(widget: "default.bluetooth", afterWidget: "spacer", path: path)
        }
    }

    private func addWidgetToDisplayed(widget: String, afterWidget: String?, path: String) {
        do {
            var content = try String(contentsOfFile: path, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")
            var newLines: [String] = []
            var insideDisplayed = false
            var inserted = false
            var bracketDepth = 0

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Detect start of displayed array
                if trimmed.hasPrefix("displayed") && trimmed.contains("[") {
                    insideDisplayed = true
                    bracketDepth = 1
                    newLines.append(line)
                    continue
                }

                if insideDisplayed && !inserted {
                    // Count brackets
                    for char in trimmed {
                        if char == "[" { bracketDepth += 1 }
                        if char == "]" { bracketDepth -= 1 }
                    }

                    // Insert after the target widget
                    if let after = afterWidget, trimmed.contains("\"\(after)\"") {
                        newLines.append(line)
                        // Determine indentation from current line
                        let indent = String(line.prefix(while: { $0.isWhitespace }))
                        newLines.append("\(indent)\"\(widget)\",")
                        inserted = true
                        continue
                    }

                    // If we hit closing bracket without finding target, insert before it
                    if bracketDepth == 0 {
                        insideDisplayed = false
                        if !inserted {
                            let indent = "    " // default indent
                            newLines.append("\(indent)\"\(widget)\",")
                            inserted = true
                        }
                    }
                }

                newLines.append(line)
            }

            if inserted {
                content = newLines.joined(separator: "\n")
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                print("[ConfigManager] Migrated config: added \(widget) to displayed widgets")
            }
        } catch {
            print("[ConfigManager] Failed to migrate config: \(error)")
        }
    }

    private func createDefaultConfig(at path: String) throws {
        let defaultTOML = """
            # If you installed yabai or aerospace without using Homebrew,
            # manually set the path to the binary. For example:
            #
            # yabai.path = "/run/current-system/sw/bin/yabai"
            # aerospace.path = ...

            theme = "system" # system, light, dark

            [widgets]
            displayed = [ # widgets on menu bar
                "default.spaces",
                "spacer",
                "default.bluetooth",
                "default.network",
                "default.battery",
                "divider",
                # { "default.time" = { time-zone = "America/Los_Angeles", format = "E d, hh:mm" } },
                "default.time"
            ]

            [widgets.default.spaces]
            space.show-key = true        # show space number (or character, if you use AeroSpace)
            window.show-title = true
            window.title.max-length = 50

            [widgets.default.battery]
            show-percentage = true
            warning-level = 30
            critical-level = 10

            [widgets.default.time]
            format = "E d, J:mm"
            calendar.format = "J:mm"

            calendar.show-events = true
            # calendar.allow-list = ["Home", "Personal"] # show only these calendars
            # calendar.deny-list = ["Work", "Boss"] # show all calendars except these

            [background]
            enabled = true
            """
        try defaultTOML.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func startWatchingFile(at path: String) {
        fileDescriptor = open(path, O_EVTONLY)
        if fileDescriptor == -1 { return }
        fileWatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor, eventMask: .write,
            queue: DispatchQueue.global())
        fileWatchSource?.setEventHandler { [weak self] in
            guard let self = self, let path = self.configFilePath else {
                return
            }
            self.parseConfigFile(at: path)
        }
        fileWatchSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
            }
        }
        fileWatchSource?.resume()
    }

    func updateConfigValue(key: String, newValue: String) {
        guard let path = configFilePath else { return }
        do {
            let currentText = try String(contentsOfFile: path, encoding: .utf8)
            let updatedText = updatedTOMLString(
                original: currentText, key: key, newValue: newValue)
            try updatedText.write(toFile: path, atomically: false, encoding: .utf8)
            // File watcher triggers parseConfigFile automatically
        } catch {
            print("Error updating config:", error)
        }
    }

    func updateConfigValue(key: String, newValue: Bool) {
        guard let path = configFilePath else { return }
        do {
            let currentText = try String(contentsOfFile: path, encoding: .utf8)
            let updatedText = updatedTOMLBool(
                original: currentText, key: key, newValue: newValue)
            try updatedText.write(toFile: path, atomically: false, encoding: .utf8)
            // File watcher triggers parseConfigFile automatically
        } catch {
            print("Error updating config:", error)
        }
    }

    func updateConfigValue(key: String, newValue: Int) {
        guard let path = configFilePath else { return }
        do {
            let currentText = try String(contentsOfFile: path, encoding: .utf8)
            let updatedText = updatedTOMLInt(
                original: currentText, key: key, newValue: newValue)
            try updatedText.write(toFile: path, atomically: false, encoding: .utf8)
            // File watcher triggers parseConfigFile automatically
        } catch {
            print("Error updating config:", error)
        }
    }

    // MARK: - Explicit Table Path Methods
    // These methods allow specifying the table path separately from the key,
    // enabling keys that contain dots (e.g., "calendar.show-events" in [widgets.default.time])

    func updateConfigValue(tablePath: String, key: String, newValue: String) {
        guard let path = configFilePath else { return }
        do {
            let currentText = try String(contentsOfFile: path, encoding: .utf8)
            let updatedText = updatedTOMLWithExplicitTable(
                original: currentText, tablePath: tablePath, key: key, valueString: "\"\(newValue)\"")
            try updatedText.write(toFile: path, atomically: false, encoding: .utf8)
            // File watcher triggers parseConfigFile automatically
        } catch {
            print("Error updating config:", error)
        }
    }

    func updateConfigValue(tablePath: String, key: String, newValue: Bool) {
        guard let path = configFilePath else { return }
        do {
            let currentText = try String(contentsOfFile: path, encoding: .utf8)
            let boolString = newValue ? "true" : "false"
            let updatedText = updatedTOMLWithExplicitTable(
                original: currentText, tablePath: tablePath, key: key, valueString: boolString)
            try updatedText.write(toFile: path, atomically: false, encoding: .utf8)
            // File watcher triggers parseConfigFile automatically
        } catch {
            print("Error updating config:", error)
        }
    }

    func updateConfigValue(tablePath: String, key: String, newValue: Int) {
        guard let path = configFilePath else { return }
        do {
            let currentText = try String(contentsOfFile: path, encoding: .utf8)
            let updatedText = updatedTOMLWithExplicitTable(
                original: currentText, tablePath: tablePath, key: key, valueString: String(newValue))
            try updatedText.write(toFile: path, atomically: false, encoding: .utf8)
            // File watcher triggers parseConfigFile automatically
        } catch {
            print("Error updating config:", error)
        }
    }

    private func updatedTOMLWithExplicitTable(
        original: String, tablePath: String, key: String, valueString: String
    ) -> String {
        let tableHeader = "[\(tablePath)]"
        let lines = original.components(separatedBy: "\n")
        var newLines: [String] = []
        var insideTargetTable = false
        var updatedKey = false
        var foundTable = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if insideTargetTable && !updatedKey {
                    newLines.append("\(key) = \(valueString)")
                    updatedKey = true
                }
                if trimmed == tableHeader {
                    foundTable = true
                    insideTargetTable = true
                } else {
                    insideTargetTable = false
                }
                newLines.append(line)
            } else {
                if insideTargetTable && !updatedKey {
                    let pattern = "^\(NSRegularExpression.escapedPattern(for: key))\\s*="
                    if line.range(of: pattern, options: .regularExpression) != nil {
                        newLines.append("\(key) = \(valueString)")
                        updatedKey = true
                        continue
                    }
                }
                newLines.append(line)
            }
        }

        if foundTable && insideTargetTable && !updatedKey {
            newLines.append("\(key) = \(valueString)")
        }

        if !foundTable {
            newLines.append("")
            newLines.append("[\(tablePath)]")
            newLines.append("\(key) = \(valueString)")
        }

        return newLines.joined(separator: "\n")
    }

    private func updatedTOMLString(
        original: String, key: String, newValue: String
    ) -> String {
        if key.contains(".") {
            let components = key.split(separator: ".").map(String.init)
            guard components.count >= 2 else {
                return original
            }

            let tablePath = components.dropLast().joined(separator: ".")
            let actualKey = components.last!

            let tableHeader = "[\(tablePath)]"
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var insideTargetTable = false
            var updatedKey = false
            var foundTable = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    if insideTargetTable && !updatedKey {
                        newLines.append("\(actualKey) = \"\(newValue)\"")
                        updatedKey = true
                    }
                    if trimmed == tableHeader {
                        foundTable = true
                        insideTargetTable = true
                    } else {
                        insideTargetTable = false
                    }
                    newLines.append(line)
                } else {
                    if insideTargetTable && !updatedKey {
                        let pattern =
                            "^\(NSRegularExpression.escapedPattern(for: actualKey))\\s*="
                        if line.range(of: pattern, options: .regularExpression)
                            != nil
                        {
                            newLines.append("\(actualKey) = \"\(newValue)\"")
                            updatedKey = true
                            continue
                        }
                    }
                    newLines.append(line)
                }
            }

            if foundTable && insideTargetTable && !updatedKey {
                newLines.append("\(actualKey) = \"\(newValue)\"")
            }

            if !foundTable {
                newLines.append("")
                newLines.append("[\(tablePath)]")
                newLines.append("\(actualKey) = \"\(newValue)\"")
            }
            return newLines.joined(separator: "\n")
        } else {
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var updatedAtLeastOnce = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.hasPrefix("#") {
                    let pattern =
                        "^\(NSRegularExpression.escapedPattern(for: key))\\s*="
                    if line.range(of: pattern, options: .regularExpression)
                        != nil
                    {
                        newLines.append("\(key) = \"\(newValue)\"")
                        updatedAtLeastOnce = true
                        continue
                    }
                }
                newLines.append(line)
            }
            if !updatedAtLeastOnce {
                newLines.append("\(key) = \"\(newValue)\"")
            }
            return newLines.joined(separator: "\n")
        }
    }

    private func updatedTOMLBool(
        original: String, key: String, newValue: Bool
    ) -> String {
        let boolString = newValue ? "true" : "false"

        if key.contains(".") {
            let components = key.split(separator: ".").map(String.init)
            guard components.count >= 2 else {
                return original
            }

            let tablePath = components.dropLast().joined(separator: ".")
            let actualKey = components.last!

            let tableHeader = "[\(tablePath)]"
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var insideTargetTable = false
            var updatedKey = false
            var foundTable = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    if insideTargetTable && !updatedKey {
                        newLines.append("\(actualKey) = \(boolString)")
                        updatedKey = true
                    }
                    if trimmed == tableHeader {
                        foundTable = true
                        insideTargetTable = true
                    } else {
                        insideTargetTable = false
                    }
                    newLines.append(line)
                } else {
                    if insideTargetTable && !updatedKey {
                        let pattern =
                            "^\(NSRegularExpression.escapedPattern(for: actualKey))\\s*="
                        if line.range(of: pattern, options: .regularExpression)
                            != nil
                        {
                            newLines.append("\(actualKey) = \(boolString)")
                            updatedKey = true
                            continue
                        }
                    }
                    newLines.append(line)
                }
            }

            if foundTable && insideTargetTable && !updatedKey {
                newLines.append("\(actualKey) = \(boolString)")
            }

            if !foundTable {
                newLines.append("")
                newLines.append("[\(tablePath)]")
                newLines.append("\(actualKey) = \(boolString)")
            }
            return newLines.joined(separator: "\n")
        } else {
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var updatedAtLeastOnce = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.hasPrefix("#") {
                    let pattern =
                        "^\(NSRegularExpression.escapedPattern(for: key))\\s*="
                    if line.range(of: pattern, options: .regularExpression)
                        != nil
                    {
                        newLines.append("\(key) = \(boolString)")
                        updatedAtLeastOnce = true
                        continue
                    }
                }
                newLines.append(line)
            }
            if !updatedAtLeastOnce {
                newLines.append("\(key) = \(boolString)")
            }
            return newLines.joined(separator: "\n")
        }
    }

    private func updatedTOMLInt(
        original: String, key: String, newValue: Int
    ) -> String {
        let intString = String(newValue)

        if key.contains(".") {
            let components = key.split(separator: ".").map(String.init)
            guard components.count >= 2 else {
                return original
            }

            let tablePath = components.dropLast().joined(separator: ".")
            let actualKey = components.last!

            let tableHeader = "[\(tablePath)]"
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var insideTargetTable = false
            var updatedKey = false
            var foundTable = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    if insideTargetTable && !updatedKey {
                        newLines.append("\(actualKey) = \(intString)")
                        updatedKey = true
                    }
                    if trimmed == tableHeader {
                        foundTable = true
                        insideTargetTable = true
                    } else {
                        insideTargetTable = false
                    }
                    newLines.append(line)
                } else {
                    if insideTargetTable && !updatedKey {
                        let pattern =
                            "^\(NSRegularExpression.escapedPattern(for: actualKey))\\s*="
                        if line.range(of: pattern, options: .regularExpression)
                            != nil
                        {
                            newLines.append("\(actualKey) = \(intString)")
                            updatedKey = true
                            continue
                        }
                    }
                    newLines.append(line)
                }
            }

            if foundTable && insideTargetTable && !updatedKey {
                newLines.append("\(actualKey) = \(intString)")
            }

            if !foundTable {
                newLines.append("")
                newLines.append("[\(tablePath)]")
                newLines.append("\(actualKey) = \(intString)")
            }
            return newLines.joined(separator: "\n")
        } else {
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var updatedAtLeastOnce = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.hasPrefix("#") {
                    let pattern =
                        "^\(NSRegularExpression.escapedPattern(for: key))\\s*="
                    if line.range(of: pattern, options: .regularExpression)
                        != nil
                    {
                        newLines.append("\(key) = \(intString)")
                        updatedAtLeastOnce = true
                        continue
                    }
                }
                newLines.append(line)
            }
            if !updatedAtLeastOnce {
                newLines.append("\(key) = \(intString)")
            }
            return newLines.joined(separator: "\n")
        }
    }

    func globalWidgetConfig(for widgetId: String) -> ConfigData {
        config.rootToml.widgets.config(for: widgetId) ?? [:]
    }

    func resolvedWidgetConfig(for item: TomlWidgetItem) -> ConfigData {
        let global = globalWidgetConfig(for: item.id)
        if item.inlineParams.isEmpty {
            return global
        }
        var merged = global
        for (key, value) in item.inlineParams {
            merged[key] = value
        }
        return merged
    }

    /// Update the widget display order in the config
    func updateWidgetOrder(_ widgetIds: [String]) {
        // Update ConfigStore in-memory state
        ConfigStore.shared.updateWidgetOrder(widgetIds: widgetIds)

        // Write directly to file for immediate file watcher compatibility
        guard let path = configFilePath else { return }
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let updatedContent = updatedTOMLWidgetOrder(original: content, widgetIds: widgetIds)
            try updatedContent.write(toFile: path, atomically: true, encoding: .utf8)
            // Force immediate config reload without waiting for file watcher
            parseConfigFile(at: path)
        } catch {
            print("Error updating widget order:", error)
        }
    }

    private func updatedTOMLWidgetOrder(original: String, widgetIds: [String]) -> String {
        let lines = original.components(separatedBy: "\n")
        var newLines: [String] = []
        var bracketDepth = 0
        var skipUntilCloseBracket = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect start of displayed array
            if trimmed.hasPrefix("displayed") && trimmed.contains("[") {
                bracketDepth = 0
                bracketDepth += countBracketsIgnoringQuotes(in: trimmed)

                // Check if the array is on a single line
                if bracketDepth == 0 {
                    // Single line array, replace it entirely
                    let widgetStrings = widgetIds.map { "\"\($0)\"" }.joined(separator: ", ")
                    newLines.append("displayed = [\(widgetStrings)]")
                } else {
                    // Multi-line array, write opening and start skipping
                    newLines.append("displayed = [")
                    skipUntilCloseBracket = true
                }
                continue
            }

            if skipUntilCloseBracket {
                // Count brackets (ignoring those inside quotes) to find the end
                bracketDepth += countBracketsIgnoringQuotes(in: trimmed)

                if bracketDepth == 0 {
                    // Write the new widget list and close bracket
                    for (index, widgetId) in widgetIds.enumerated() {
                        let comma = index < widgetIds.count - 1 ? "," : ""
                        newLines.append("    \"\(widgetId)\"\(comma)")
                    }
                    newLines.append("]")
                    skipUntilCloseBracket = false
                }
                continue
            }

            newLines.append(line)
        }

        return newLines.joined(separator: "\n")
    }

    /// Count bracket balance while ignoring brackets inside quoted strings
    private func countBracketsIgnoringQuotes(in text: String) -> Int {
        var depth = 0
        var inString = false
        var prevChar: Character = "\0"

        for char in text {
            if char == "\"" && prevChar != "\\" {
                inString.toggle()
            } else if !inString {
                if char == "[" { depth += 1 }
                if char == "]" { depth -= 1 }
            }
            prevChar = char
        }

        return depth
    }
}
