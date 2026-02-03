import Foundation
import SwiftUI

/// Typed configuration model - single source of truth for all settings
struct BarikConfig: Codable, Equatable {
    var theme: Theme = .system
    var widgets: WidgetLayout = .init()
    var zonedLayout: ZonedLayout = .default
    var foreground: ForegroundSettings = .init()
    var background: BackgroundSettings = .init()
    var yabai: YabaiSettings = .init()
    var aerospace: AerospaceSettings = .init()

    enum Theme: String, Codable, CaseIterable {
        case system, light, dark
    }

    struct WidgetLayout: Codable, Equatable {
        var displayed: [WidgetItem] = WidgetItem.defaultLayout
        var settings: [String: WidgetSettings] = [:]

        private struct DynamicKey: CodingKey {
            var stringValue: String
            var intValue: Int? = nil

            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        init(displayed: [WidgetItem] = WidgetItem.defaultLayout, settings: [String: WidgetSettings] = [:]) {
            self.displayed = displayed
            self.settings = settings
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            let displayedKey = DynamicKey(stringValue: "displayed")!
            self.displayed = (try? container.decode([WidgetItem].self, forKey: displayedKey)) ?? []

            var tempSettings: [String: WidgetSettings] = [:]
            for key in container.allKeys where key.stringValue != "displayed" {
                let nested = try container.nestedContainer(keyedBy: DynamicKey.self, forKey: key)
                var values: [String: AnyCodableValue] = [:]
                for nestedKey in nested.allKeys {
                    let value = try nested.decode(AnyCodableValue.self, forKey: nestedKey)
                    values[nestedKey.stringValue] = value
                }
                tempSettings[key.stringValue] = WidgetSettings(values: values)
            }
            self.settings = tempSettings
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicKey.self)
            let displayedKey = DynamicKey(stringValue: "displayed")!
            try container.encode(displayed, forKey: displayedKey)
            for (widgetId, settings) in settings {
                guard let key = DynamicKey(stringValue: widgetId) else { continue }
                var nested = container.nestedContainer(keyedBy: DynamicKey.self, forKey: key)
                for (settingKey, value) in settings.values {
                    guard let nestedKey = DynamicKey(stringValue: settingKey) else { continue }
                    try nested.encode(value, forKey: nestedKey)
                }
            }
        }
    }

    struct WidgetItem: Codable, Equatable, Identifiable {
        let widgetId: String
        var instanceId: UUID
        var inlineConfig: [String: AnyCodableValue]?

        var id: UUID { instanceId }

        init(widgetId: String, instanceId: UUID = UUID(), inlineConfig: [String: AnyCodableValue]? = nil) {
            self.widgetId = widgetId
            self.instanceId = instanceId
            self.inlineConfig = inlineConfig
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let strValue = try? container.decode(String.self) {
                self.widgetId = strValue
                self.instanceId = UUID()
                self.inlineConfig = nil
                return
            }

            let dictValue = try container.decode([String: [String: AnyCodableValue]].self)
            guard dictValue.count == 1, let (widgetId, params) = dictValue.first else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid widget item")
            }
            self.widgetId = widgetId
            self.instanceId = UUID()
            self.inlineConfig = params
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            if let inline = inlineConfig, !inline.isEmpty {
                try container.encode([widgetId: inline])
            } else {
                try container.encode(widgetId)
            }
        }

        static let defaultLayout: [WidgetItem] = [
            .init(widgetId: "default.spaces"),
            .init(widgetId: "spacer"),
            .init(widgetId: "default.bluetooth"),
            .init(widgetId: "default.network"),
            .init(widgetId: "default.battery"),
            .init(widgetId: "divider"),
            .init(widgetId: "default.time")
        ]
    }

    struct WidgetSettings: Codable, Equatable {
        var values: [String: AnyCodableValue]

        init(values: [String: AnyCodableValue] = [:]) {
            self.values = values
        }
    }

    struct ForegroundSettings: Codable, Equatable {
        var position: Position = .top
        var height: DimensionValue = .barikDefault
        var width: DimensionValue = .barikDefault
        var horizontalPadding: CGFloat = 8
        var spacing: CGFloat = 15
        var showClock: Bool = true
        var showBattery: Bool = true
        var showNetwork: Bool = true
        var widgetsBackground: WidgetsBackgroundSettings = .init()

        enum Position: String, Codable {
            case top, bottom
        }

        enum CodingKeys: String, CodingKey {
            case position, height, width, spacing
            case horizontalPadding = "horizontal-padding"
            case showClock = "show-clock"
            case showBattery = "show-battery"
            case showNetwork = "show-network"
            case widgetsBackground = "widgets-background"
        }

        func resolveHeight() -> CGFloat {
            switch height {
            case .barikDefault:
                return CGFloat(Constants.menuBarHeight)
            case .menuBar:
                return NSApplication.shared.mainMenu.map({ CGFloat($0.menuBarHeight) }) ?? CGFloat(Constants.menuBarHeight)
            case .custom(let value):
                return value
            }
        }

        func resolveWidth() -> CGFloat {
            switch width {
            case .barikDefault:
                return CGFloat(Constants.menuBarWidth)
            case .menuBar:
                return CGFloat(Constants.menuBarWidth)
            case .custom(let value):
                return value
            }
        }
    }

    struct WidgetsBackgroundSettings: Codable, Equatable {
        var displayed: Bool = false
        var blur: Int = 3

        var blurMaterial: Material {
            switch blur {
            case 1: return .ultraThin
            case 2: return .thin
            case 3: return .regular
            case 4: return .thick
            case 5: return .ultraThick
            default: return .regular
            }
        }
    }

    struct BackgroundSettings: Codable, Equatable {
        var enabled: Bool = true
        var height: DimensionValue = .barikDefault
        var blur: Int = 3

        func resolveHeight() -> CGFloat? {
            switch height {
            case .barikDefault:
                return CGFloat(Constants.menuBarHeight)
            case .menuBar:
                return NSApplication.shared.mainMenu.map({ CGFloat($0.menuBarHeight) })
            case .custom(let value):
                return value
            }
        }

        var blurMaterial: Material {
            switch blur {
            case 1: return .ultraThin
            case 2: return .thin
            case 3: return .regular
            case 4: return .thick
            case 5: return .ultraThick
            default: return .regular
            }
        }
    }

    struct YabaiSettings: Codable, Equatable {
        var path: String

        init(path: String = YabaiSettings.resolveDefaultPath()) {
            self.path = path
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decoded = try? container.decode(String.self, forKey: .path)
            self.path = decoded ?? YabaiSettings.resolveDefaultPath()
        }

        enum CodingKeys: String, CodingKey {
            case path
        }

        private static func resolveDefaultPath() -> String {
            if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/yabai") {
                return "/opt/homebrew/bin/yabai"
            }
            if FileManager.default.fileExists(atPath: "/usr/local/bin/yabai") {
                return "/usr/local/bin/yabai"
            }
            return "/opt/homebrew/bin/yabai"
        }
    }

    struct AerospaceSettings: Codable, Equatable {
        var path: String

        init(path: String = AerospaceSettings.resolveDefaultPath()) {
            self.path = path
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decoded = try? container.decode(String.self, forKey: .path)
            self.path = decoded ?? AerospaceSettings.resolveDefaultPath()
        }

        enum CodingKeys: String, CodingKey {
            case path
        }

        private static func resolveDefaultPath() -> String {
            if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/aerospace") {
                return "/opt/homebrew/bin/aerospace"
            }
            if FileManager.default.fileExists(atPath: "/usr/local/bin/aerospace") {
                return "/usr/local/bin/aerospace"
            }
            return "/opt/homebrew/bin/aerospace"
        }
    }

    enum DimensionValue: Codable, Equatable {
        case barikDefault
        case menuBar
        case custom(CGFloat)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let str = try? container.decode(String.self) {
                switch str {
                case "default": self = .barikDefault
                case "menu-bar": self = .menuBar
                default:
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown dimension value: \(str)")
                }
            } else if let num = try? container.decode(Double.self) {
                self = .custom(CGFloat(num))
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected string or number")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .barikDefault: try container.encode("default")
            case .menuBar: try container.encode("menu-bar")
            case .custom(let value): try container.encode(Double(value))
            }
        }
    }
}

/// Type-erased codable value for dynamic config fields
enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let arr = try? container.decode([AnyCodableValue].self) {
            self = .array(arr)
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dict)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown value type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let v) = self { return v }
        return nil
    }

    var arrayValue: [AnyCodableValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    var dictionaryValue: [String: AnyCodableValue]? {
        if case .dictionary(let v) = self { return v }
        return nil
    }
}
