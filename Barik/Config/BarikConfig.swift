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
    }

    struct WidgetsBackgroundSettings: Codable, Equatable {
        var displayed: Bool = false
        var blur: Int = 3
    }

    struct BackgroundSettings: Codable, Equatable {
        var enabled: Bool = true
        var height: DimensionValue = .barikDefault
        var blur: Int = 3
    }

    struct YabaiSettings: Codable, Equatable {
        var path: String?
    }

    struct AerospaceSettings: Codable, Equatable {
        var path: String?
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
}

// MARK: - Conversion from legacy TOMLValue

extension AnyCodableValue {
    init(from tomlValue: TOMLValue) {
        switch tomlValue {
        case .string(let s): self = .string(s)
        case .int(let i): self = .int(i)
        case .double(let d): self = .double(d)
        case .bool(let b): self = .bool(b)
        case .array(let arr): self = .array(arr.map { AnyCodableValue(from: $0) })
        case .dictionary(let dict): self = .dictionary(dict.mapValues { AnyCodableValue(from: $0) })
        case .null: self = .null
        }
    }

    func toTOMLValue() -> TOMLValue {
        switch self {
        case .string(let s): return .string(s)
        case .int(let i): return .int(i)
        case .double(let d): return .double(d)
        case .bool(let b): return .bool(b)
        case .array(let arr): return .array(arr.map { $0.toTOMLValue() })
        case .dictionary(let dict): return .dictionary(dict.mapValues { $0.toTOMLValue() })
        case .null: return .null
        }
    }
}
