import Foundation
import SwiftUI
import Combine

/// Observable config store - read-only cache, ConfigManager owns file I/O
@Observable
final class ConfigStore {
    static let shared = ConfigStore()

    private(set) var config: BarikConfig = .init()
    private var onChangeCallbacks: [(BarikConfig) -> Void] = []

    private init() {
        // Migration and loading is done via ConfigMigration.migrateIfNeeded()
        // which is called from ConfigManager during app startup
    }

    /// Initialize from migrated config
    func initialize(with config: BarikConfig) {
        self.config = config
    }

    // MARK: - In-Memory Updates (ConfigManager handles persistence)

    /// Update a config value using a keypath (in-memory only)
    func update<T>(_ keyPath: WritableKeyPath<BarikConfig, T>, to value: T) {
        config[keyPath: keyPath] = value
        notifyObservers()
    }

    /// Update widget order in memory (ConfigManager handles file writing)
    func updateWidgetOrder(widgetIds: [String]) {
        config.widgets.displayed = widgetIds.map { BarikConfig.WidgetItem(widgetId: $0) }
        notifyObservers()
    }

    // MARK: - Legacy Key Updates (in-memory sync with ConfigManager)

    /// Update config using legacy dotted key path (e.g., "experimental.foreground.position")
    func updateLegacyKey(_ key: String, stringValue: String) {
        let components = key.split(separator: ".").map(String.init)
        applyLegacyUpdate(components: components, stringValue: stringValue)
        notifyObservers()
    }

    func updateLegacyKey(_ key: String, boolValue: Bool) {
        let components = key.split(separator: ".").map(String.init)
        applyLegacyBoolUpdate(components: components, boolValue: boolValue)
        notifyObservers()
    }

    func updateLegacyKey(_ key: String, intValue: Int) {
        let components = key.split(separator: ".").map(String.init)
        applyLegacyIntUpdate(components: components, intValue: intValue)
        notifyObservers()
    }

    private func applyLegacyUpdate(components: [String], stringValue: String) {
        // Map legacy keys to typed config
        switch components {
        case ["theme"]:
            if let theme = BarikConfig.Theme(rawValue: stringValue) {
                config.theme = theme
            }
        case ["experimental", "foreground", "position"]:
            if let pos = BarikConfig.ForegroundSettings.Position(rawValue: stringValue) {
                config.foreground.position = pos
            }
        default:
            print("[ConfigStore] Unknown legacy key: \(components.joined(separator: "."))")
        }
    }

    private func applyLegacyBoolUpdate(components: [String], boolValue: Bool) {
        switch components {
        case ["background", "enabled"]:
            config.background.enabled = boolValue
        case ["experimental", "foreground", "show-clock"]:
            config.foreground.showClock = boolValue
        case ["experimental", "foreground", "show-battery"]:
            config.foreground.showBattery = boolValue
        case ["experimental", "foreground", "show-network"]:
            config.foreground.showNetwork = boolValue
        case ["experimental", "foreground", "widgets-background", "displayed"]:
            config.foreground.widgetsBackground.displayed = boolValue
        default:
            print("[ConfigStore] Unknown legacy bool key: \(components.joined(separator: "."))")
        }
    }

    private func applyLegacyIntUpdate(components: [String], intValue: Int) {
        switch components {
        case ["experimental", "foreground", "spacing"]:
            config.foreground.spacing = CGFloat(intValue)
        case ["experimental", "foreground", "horizontal-padding"]:
            config.foreground.horizontalPadding = CGFloat(intValue)
        case ["experimental", "foreground", "widgets-background", "blur"]:
            config.foreground.widgetsBackground.blur = intValue
        case ["background", "blur"]:
            config.background.blur = intValue
        default:
            print("[ConfigStore] Unknown legacy int key: \(components.joined(separator: "."))")
        }
    }

    // MARK: - Change Observation

    func onChange(_ callback: @escaping (BarikConfig) -> Void) {
        onChangeCallbacks.append(callback)
    }

    func removeAllObservers() {
        onChangeCallbacks.removeAll()
    }

    private func notifyObservers() {
        for callback in onChangeCallbacks {
            callback(config)
        }
    }
}

// MARK: - TOML Encoder (Simple, focused encoder for our config structure)

enum ConfigTOMLEncoder {
    static func encode(_ config: BarikConfig) -> String {
        var lines: [String] = []

        // Theme
        lines.append("theme = \"\(config.theme.rawValue)\"")
        lines.append("")

        // Widgets section
        lines.append("[widgets]")
        lines.append("displayed = [")
        for (index, item) in config.widgets.displayed.enumerated() {
            let comma = index < config.widgets.displayed.count - 1 ? "," : ""
            if let inline = item.inlineConfig, !inline.isEmpty {
                let params = encodeInlineParams(inline)
                lines.append("    { \"\(item.widgetId)\" = { \(params) } }\(comma)")
            } else {
                lines.append("    \"\(item.widgetId)\"\(comma)")
            }
        }
        lines.append("]")
        lines.append("")

        // Widget-specific settings
        for (widgetId, settings) in config.widgets.settings {
            if !settings.values.isEmpty {
                lines.append("[widgets.\(widgetId)]")
                for (key, value) in settings.values.sorted(by: { $0.key < $1.key }) {
                    lines.append("\(key) = \(encodeValue(value))")
                }
                lines.append("")
            }
        }

        // Background
        lines.append("[background]")
        lines.append("enabled = \(config.background.enabled)")
        if config.background.blur != 3 {
            lines.append("blur = \(config.background.blur)")
        }
        lines.append("")

        // Experimental foreground (only if non-default)
        if config.foreground != BarikConfig.ForegroundSettings() {
            lines.append("[experimental.foreground]")
            if config.foreground.position != .top {
                lines.append("position = \"\(config.foreground.position.rawValue)\"")
            }
            if config.foreground.spacing != 15 {
                lines.append("spacing = \(Int(config.foreground.spacing))")
            }
            if config.foreground.horizontalPadding != 8 {
                lines.append("horizontal-padding = \(Int(config.foreground.horizontalPadding))")
            }
            if !config.foreground.showClock {
                lines.append("show-clock = false")
            }
            if !config.foreground.showBattery {
                lines.append("show-battery = false")
            }
            if !config.foreground.showNetwork {
                lines.append("show-network = false")
            }
            lines.append("")
        }

        // Yabai path (only if custom)
        if let yabaiPath = config.yabai.path {
            lines.append("[yabai]")
            lines.append("path = \"\(yabaiPath)\"")
            lines.append("")
        }

        // Aerospace path (only if custom)
        if let aerospacePath = config.aerospace.path {
            lines.append("[aerospace]")
            lines.append("path = \"\(aerospacePath)\"")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func encodeValue(_ value: AnyCodableValue) -> String {
        switch value {
        case .string(let s): return "\"\(s)\""
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .array(let arr): return "[\(arr.map { encodeValue($0) }.joined(separator: ", "))]"
        case .dictionary(let dict):
            let pairs = dict.sorted(by: { $0.key < $1.key }).map { "\($0.key) = \(encodeValue($0.value))" }
            return "{ \(pairs.joined(separator: ", ")) }"
        case .null: return "\"\""
        }
    }

    private static func encodeInlineParams(_ params: [String: AnyCodableValue]) -> String {
        params.sorted(by: { $0.key < $1.key })
            .map { "\($0.key) = \(encodeValue($0.value))" }
            .joined(separator: ", ")
    }
}
