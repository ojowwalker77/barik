import Foundation

// MARK: - Zone Types

/// The three zones in the menu bar layout
enum Zone: String, Codable, CaseIterable, Hashable {
    case left
    case center
    case right
}

/// Compaction levels for widgets when space is limited
enum CompactionLevel: String, Codable, CaseIterable, Comparable {
    case full      // Full widget with all details
    case compact   // Reduced size, essential info only
    case iconOnly  // Just the icon
    case hidden    // Not visible (in overflow menu)

    static func < (lhs: CompactionLevel, rhs: CompactionLevel) -> Bool {
        let order: [CompactionLevel] = [.full, .compact, .iconOnly, .hidden]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

// MARK: - Widget Size Specification

/// Defines the size of a widget at different compaction levels
struct WidgetSizeSpec: Codable, Equatable, Hashable {
    /// Column count at full size
    var full: Int

    /// Column count at compact size (nil = can't compact)
    var compact: Int?

    /// Column count at icon-only size (nil = can't show icon-only)
    var iconOnly: Int?

    init(full: Int, compact: Int? = nil, iconOnly: Int? = nil) {
        self.full = full
        self.compact = compact
        self.iconOnly = iconOnly
    }

    /// Get the column count for a given compaction level
    func columns(for level: CompactionLevel) -> Int? {
        switch level {
        case .full: return full
        case .compact: return compact ?? full
        case .iconOnly: return iconOnly ?? compact ?? full
        case .hidden: return 0
        }
    }

    /// Check if widget supports a given compaction level
    func supports(_ level: CompactionLevel) -> Bool {
        switch level {
        case .full: return true
        case .compact: return compact != nil
        case .iconOnly: return iconOnly != nil
        case .hidden: return true
        }
    }
}

// MARK: - Zone Configuration

/// Configuration for a single zone
struct ZoneConfig: Codable, Equatable {
    /// Minimum columns this zone must have
    var minColumns: Int

    /// Maximum columns (nil = unlimited/fills available)
    var maxColumns: Int?

    /// Whether this zone is anchored to its position (center only)
    /// Anchored zones try to stay centered, non-anchored zones grow to fill
    var isAnchored: Bool

    init(minColumns: Int = 0, maxColumns: Int? = nil, isAnchored: Bool = false) {
        self.minColumns = minColumns
        self.maxColumns = maxColumns
        self.isAnchored = isAnchored
    }

    static let leftDefault = ZoneConfig(minColumns: 0, maxColumns: nil, isAnchored: false)
    static let centerDefault = ZoneConfig(minColumns: 0, maxColumns: nil, isAnchored: true)
    static let rightDefault = ZoneConfig(minColumns: 0, maxColumns: nil, isAnchored: false)
}

// MARK: - Compaction Configuration

/// Configuration for automatic compaction behavior
struct CompactionConfig: Codable, Equatable {
    /// Whether compaction is enabled
    var enabled: Bool

    /// Threshold (0-1) at which compaction starts (e.g., 0.85 = 85% full)
    var threshold: Double

    /// Strategy for choosing which widgets to compact first
    var strategy: CompactionStrategy

    init(enabled: Bool = true, threshold: Double = 0.85, strategy: CompactionStrategy = .priorityFirst) {
        self.enabled = enabled
        self.threshold = threshold
        self.strategy = strategy
    }

    enum CompactionStrategy: String, Codable {
        /// Compact lowest priority widgets first
        case priorityFirst
        /// Compact from the edges inward
        case edgesFirst
        /// Compact newest (most recently added) widgets first
        case newestFirst
    }
}

// MARK: - Zoned Widget Item

/// A widget item placed in a specific zone
struct ZonedWidgetItem: Codable, Equatable, Identifiable {
    /// The widget type ID (e.g., "default.battery")
    var widgetId: String

    /// Unique instance ID for this placement
    var instanceId: UUID

    /// Display order within the zone (lower = earlier)
    var order: Int

    /// Priority for compaction (higher = more important, compacted last)
    var priority: Int

    /// Minimum compaction level (widget won't compact below this)
    var minSize: CompactionLevel

    /// Inline configuration overrides
    var inlineConfig: [String: AnyCodableValue]?

    var id: UUID { instanceId }

    init(
        widgetId: String,
        instanceId: UUID = UUID(),
        order: Int = 0,
        priority: Int = 50,
        minSize: CompactionLevel = .iconOnly,
        inlineConfig: [String: AnyCodableValue]? = nil
    ) {
        self.widgetId = widgetId
        self.instanceId = instanceId
        self.order = order
        self.priority = priority
        self.minSize = minSize
        self.inlineConfig = inlineConfig
    }
}

// MARK: - Zoned Layout

/// The complete zoned layout configuration
struct ZonedLayout: Codable, Equatable {
    var left: [ZonedWidgetItem]
    var center: [ZonedWidgetItem]
    var right: [ZonedWidgetItem]

    var leftConfig: ZoneConfig
    var centerConfig: ZoneConfig
    var rightConfig: ZoneConfig

    var compaction: CompactionConfig

    init(
        left: [ZonedWidgetItem] = [],
        center: [ZonedWidgetItem] = [],
        right: [ZonedWidgetItem] = [],
        leftConfig: ZoneConfig = .leftDefault,
        centerConfig: ZoneConfig = .centerDefault,
        rightConfig: ZoneConfig = .rightDefault,
        compaction: CompactionConfig = .init()
    ) {
        self.left = left
        self.center = center
        self.right = right
        self.leftConfig = leftConfig
        self.centerConfig = centerConfig
        self.rightConfig = rightConfig
        self.compaction = compaction
    }

    enum CodingKeys: String, CodingKey {
        case left, center, right
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let leftIds = (try? container.decode([String].self, forKey: .left)) ?? []
        let centerIds = (try? container.decode([String].self, forKey: .center)) ?? []
        let rightIds = (try? container.decode([String].self, forKey: .right)) ?? []

        func makeItems(_ ids: [String]) -> [ZonedWidgetItem] {
            ids.enumerated().map { index, widgetId in
                ZonedWidgetItem(widgetId: widgetId, order: index)
            }
        }

        self.left = makeItems(leftIds)
        self.center = makeItems(centerIds)
        self.right = makeItems(rightIds)
        self.leftConfig = .leftDefault
        self.centerConfig = .centerDefault
        self.rightConfig = .rightDefault
        self.compaction = .init()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(left.map { $0.widgetId }, forKey: .left)
        try container.encode(center.map { $0.widgetId }, forKey: .center)
        try container.encode(right.map { $0.widgetId }, forKey: .right)
    }

    /// Get items for a specific zone
    func items(for zone: Zone) -> [ZonedWidgetItem] {
        switch zone {
        case .left: return left
        case .center: return center
        case .right: return right
        }
    }

    /// Get all items across all zones
    var allItems: [ZonedWidgetItem] {
        left + center + right
    }

    /// Get config for a specific zone
    func config(for zone: Zone) -> ZoneConfig {
        switch zone {
        case .left: return leftConfig
        case .center: return centerConfig
        case .right: return rightConfig
        }
    }

    /// Create default layout
    static let `default` = ZonedLayout(
        left: [
            ZonedWidgetItem(widgetId: "default.spaces", order: 0, priority: 90)
        ],
        center: [
            ZonedWidgetItem(widgetId: "default.time", order: 0, priority: 100)
        ],
        right: [
            ZonedWidgetItem(widgetId: "default.bluetooth", order: 0, priority: 60),
            ZonedWidgetItem(widgetId: "default.network", order: 1, priority: 70),
            ZonedWidgetItem(widgetId: "default.battery", order: 2, priority: 80)
        ]
    )
}
