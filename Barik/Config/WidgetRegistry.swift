import Foundation

/// Defines metadata for a widget type that can appear in the toolbar
struct WidgetDefinition: Identifiable, Hashable {
    let id: String          // "default.battery", "spacer", etc.
    let name: String        // "Battery", "Spacer"
    let icon: String        // SF Symbol name
    let category: Category
    let allowMultiple: Bool // spacer=true, battery=false
    let gridWidth: Int      // Width in grid slots (1, 2, 3, etc.) - maps to sizes.full

    // Zone-based layout properties
    let sizes: WidgetSizeSpec       // Size at different compaction levels
    let defaultZone: Zone           // Default zone for new placements
    let defaultPriority: Int        // Default compaction priority (higher = more important)
    let canGrow: Bool               // Whether widget can expand to fill space

    enum Category: String, CaseIterable {
        case data    // Real-time data widgets (battery, network, time)
        case layout  // Layout helpers (spacer, divider)
        case control // Control widgets (settings)
    }

    init(
        id: String,
        name: String,
        icon: String,
        category: Category,
        allowMultiple: Bool,
        gridWidth: Int,
        sizes: WidgetSizeSpec? = nil,
        defaultZone: Zone = .right,
        defaultPriority: Int = 50,
        canGrow: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.category = category
        self.allowMultiple = allowMultiple
        self.gridWidth = gridWidth
        self.sizes = sizes ?? WidgetSizeSpec(full: gridWidth)
        self.defaultZone = defaultZone
        self.defaultPriority = defaultPriority
        self.canGrow = canGrow
    }
}

/// Central registry of all available widgets
struct WidgetRegistry {
    static let all: [WidgetDefinition] = [
        // Data widgets
        WidgetDefinition(
            id: "default.spaces",
            name: "Spaces",
            icon: "square.grid.2x2",
            category: .data,
            allowMultiple: false,
            gridWidth: 3,
            sizes: WidgetSizeSpec(full: 3, compact: 2, iconOnly: 1),
            defaultZone: .left,
            defaultPriority: 90
        ),
        WidgetDefinition(
            id: "default.battery",
            name: "Battery",
            icon: "battery.100",
            category: .data,
            allowMultiple: false,
            gridWidth: 2,
            sizes: WidgetSizeSpec(full: 2, compact: 1, iconOnly: 1),
            defaultZone: .right,
            defaultPriority: 80
        ),
        WidgetDefinition(
            id: "default.network",
            name: "Network",
            icon: "wifi",
            category: .data,
            allowMultiple: false,
            gridWidth: 2,
            sizes: WidgetSizeSpec(full: 2, compact: 1, iconOnly: 1),
            defaultZone: .right,
            defaultPriority: 70
        ),
        WidgetDefinition(
            id: "default.time",
            name: "Time",
            icon: "clock",
            category: .data,
            allowMultiple: false,
            gridWidth: 3,
            sizes: WidgetSizeSpec(full: 3, compact: 2, iconOnly: 1),
            defaultZone: .center,
            defaultPriority: 100
        ),
        WidgetDefinition(
            id: "default.nowplaying",
            name: "Now Playing",
            icon: "music.note",
            category: .data,
            allowMultiple: false,
            gridWidth: 3,
            sizes: WidgetSizeSpec(full: 3, compact: 2, iconOnly: 1),
            defaultZone: .center,
            defaultPriority: 60
        ),
        WidgetDefinition(
            id: "default.bluetooth",
            name: "Bluetooth",
            icon: "wave.3.right",
            category: .data,
            allowMultiple: false,
            gridWidth: 2,
            sizes: WidgetSizeSpec(full: 2, compact: 1, iconOnly: 1),
            defaultZone: .right,
            defaultPriority: 60
        ),

        // Layout widgets
        WidgetDefinition(
            id: "spacer",
            name: "Flexible Space",
            icon: "arrow.left.and.right",
            category: .layout,
            allowMultiple: true,
            gridWidth: 2,
            sizes: WidgetSizeSpec(full: 2, compact: 1, iconOnly: nil),
            defaultZone: .left,
            defaultPriority: 10,
            canGrow: true
        ),
        WidgetDefinition(
            id: "divider",
            name: "Divider",
            icon: "minus",
            category: .layout,
            allowMultiple: true,
            gridWidth: 1,
            sizes: WidgetSizeSpec(full: 1, compact: nil, iconOnly: nil),
            defaultZone: .right,
            defaultPriority: 20
        ),
    ]

    /// Get widget definition by ID
    static func widget(for id: String) -> WidgetDefinition? {
        all.first { $0.id == id }
    }

    /// Get available widgets, excluding those already in use (unless allowMultiple)
    static func available(excluding currentIds: [String]) -> [WidgetDefinition] {
        all.filter { definition in
            definition.allowMultiple || !currentIds.contains(definition.id)
        }
    }

    /// Default widget layout
    static let defaultLayout: [String] = [
        "default.spaces",
        "spacer",
        "default.bluetooth",
        "default.network",
        "default.battery",
        "divider",
        "default.time"
    ]
}
