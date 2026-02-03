import Foundation
import SwiftUI

/// Observable config store - read-only cache, ConfigManager owns file I/O
@Observable
final class ConfigStore {
    static let shared = ConfigStore()

    private(set) var config: BarikConfig = .init()
    private var onChangeCallbacks: [(BarikConfig) -> Void] = []

    private init() {}

    /// Initialize from migrated config
    func initialize(with config: BarikConfig) {
        self.config = config
    }

    func replaceConfig(_ config: BarikConfig) {
        self.config = config
        notifyObservers()
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

    /// Update zoned layout in memory
    func updateZonedLayout(left: [ZonedWidgetItem], center: [ZonedWidgetItem], right: [ZonedWidgetItem]) {
        config.zonedLayout.left = left
        config.zonedLayout.center = center
        config.zonedLayout.right = right
        notifyObservers()
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

        // Zoned layout
        lines.append("[zonedLayout]")
        lines.append("left = \(encodeStringArray(config.zonedLayout.left.map { $0.widgetId }))")
        lines.append("center = \(encodeStringArray(config.zonedLayout.center.map { $0.widgetId }))")
        lines.append("right = \(encodeStringArray(config.zonedLayout.right.map { $0.widgetId }))")
        lines.append("")

        // Background
        lines.append("[background]")
        lines.append("enabled = \(config.background.enabled)")
        if config.background.height != .barikDefault {
            lines.append("height = \(encodeDimension(config.background.height))")
        }
        if config.background.blur != 3 {
            lines.append("blur = \(config.background.blur)")
        }
        if config.background.mode != .blur {
            lines.append("mode = \"\(config.background.mode.rawValue)\"")
        }
        lines.append("")

        // Foreground (only if non-default)
        if config.foreground != BarikConfig.ForegroundSettings() {
            lines.append("[foreground]")
            if config.foreground.position != .top {
                lines.append("position = \"\(config.foreground.position.rawValue)\"")
            }
            if config.foreground.height != .barikDefault {
                lines.append("height = \(encodeDimension(config.foreground.height))")
            }
            if config.foreground.width != .barikDefault {
                lines.append("width = \(encodeDimension(config.foreground.width))")
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
            if config.foreground.widgetsBackground.displayed
                || config.foreground.widgetsBackground.blur != 3
            {
                lines.append("")
                lines.append("[foreground.widgets-background]")
                if config.foreground.widgetsBackground.displayed {
                    lines.append("displayed = true")
                }
                if config.foreground.widgetsBackground.blur != 3 {
                    lines.append("blur = \(config.foreground.widgetsBackground.blur)")
                }
            }
            lines.append("")
        }

        // Yabai path (only if custom)
        lines.append("[yabai]")
        lines.append("path = \"\(config.yabai.path)\"")
        lines.append("")

        // Aerospace path (only if custom)
        lines.append("[aerospace]")
        lines.append("path = \"\(config.aerospace.path)\"")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func encodeDimension(_ value: BarikConfig.DimensionValue) -> String {
        switch value {
        case .barikDefault:
            return "\"default\""
        case .menuBar:
            return "\"menu-bar\""
        case .custom(let number):
            return String(Double(number))
        }
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

    private static func encodeStringArray(_ values: [String]) -> String {
        let joined = values.map { "\"\($0)\"" }.joined(separator: ", ")
        return "[\(joined)]"
    }
}
