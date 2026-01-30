import Foundation
import TOMLDecoder

/// Handles migration from legacy TOML config to new typed config
enum ConfigMigration {

    struct MigrationResult {
        let config: BarikConfig
        let path: URL
        let didMigrate: Bool
    }

    /// Migrate config if needed, returning the typed config and path
    static func migrateIfNeeded() -> MigrationResult {
        let homePath = FileManager.default.homeDirectoryForCurrentUser

        // Config locations in order of preference
        let legacyPath = homePath.appendingPathComponent(".barik-config.toml")
        let newDirPath = homePath.appendingPathComponent(".config/barik")
        let newPath = newDirPath.appendingPathComponent("config.toml")

        // Check for existing configs
        let legacyExists = FileManager.default.fileExists(atPath: legacyPath.path)
        let newExists = FileManager.default.fileExists(atPath: newPath.path)

        // If new config exists, load it
        if newExists {
            if let config = loadConfig(from: newPath) {
                return MigrationResult(config: config, path: newPath, didMigrate: false)
            }
        }

        // If legacy exists, migrate it
        if legacyExists {
            if let legacyConfig = loadLegacyConfig(from: legacyPath) {
                let newConfig = convertFromLegacy(legacyConfig)

                // Ensure directory exists
                try? FileManager.default.createDirectory(at: newDirPath, withIntermediateDirectories: true)

                // Save new config
                let tomlString = ConfigTOMLEncoder.encode(newConfig)
                try? tomlString.write(to: newPath, atomically: true, encoding: .utf8)

                // Backup old config (remove existing backup first to avoid move failure)
                let backupPath = legacyPath.appendingPathExtension("backup")
                try? FileManager.default.removeItem(at: backupPath)
                try? FileManager.default.moveItem(at: legacyPath, to: backupPath)

                print("[ConfigMigration] Migrated config from \(legacyPath.path) to \(newPath.path)")
                print("[ConfigMigration] Old config backed up to \(backupPath.path)")

                return MigrationResult(config: newConfig, path: newPath, didMigrate: true)
            }
        }

        // No existing config - create default at legacy location (simpler for users)
        let defaultConfig = BarikConfig()
        let tomlString = ConfigTOMLEncoder.encode(defaultConfig)
        try? tomlString.write(to: legacyPath, atomically: true, encoding: .utf8)
        print("[ConfigMigration] Created default config at \(legacyPath.path)")

        return MigrationResult(config: defaultConfig, path: legacyPath, didMigrate: false)
    }

    // MARK: - Loading

    private static func loadConfig(from url: URL) -> BarikConfig? {
        // For now, we still use TOMLDecoder to parse, then convert
        // This maintains compatibility with hand-edited files
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        // Try to decode as RootToml (legacy format) since TOML structure hasn't changed
        guard let rootToml = try? TOMLDecoder().decode(RootToml.self, from: content) else {
            return nil
        }

        return convertFromLegacy(rootToml)
    }

    private static func loadLegacyConfig(from url: URL) -> RootToml? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        return try? TOMLDecoder().decode(RootToml.self, from: content)
    }

    // MARK: - Conversion

    private static func convertFromLegacy(_ root: RootToml) -> BarikConfig {
        var config = BarikConfig()

        // Theme
        if let themeStr = root.theme, let theme = BarikConfig.Theme(rawValue: themeStr) {
            config.theme = theme
        }

        // Widgets - preserve order and inline configs
        config.widgets.displayed = root.widgets.displayed.map { item in
            var inlineConfig: [String: AnyCodableValue]? = nil
            if !item.inlineParams.isEmpty {
                inlineConfig = item.inlineParams.mapValues { AnyCodableValue(from: $0) }
            }
            return BarikConfig.WidgetItem(
                widgetId: item.id,
                inlineConfig: inlineConfig
            )
        }

        // Migrate flat displayed array to zoned layout
        config.zonedLayout = migrateToZonedLayout(displayed: root.widgets.displayed)

        // Widget-specific settings
        for (widgetId, settings) in root.widgets.others {
            config.widgets.settings[widgetId] = BarikConfig.WidgetSettings(
                values: settings.mapValues { AnyCodableValue(from: $0) }
            )
        }

        // Foreground settings
        if let exp = root.experimental {
            let fg = exp.foreground
            config.foreground.position = fg.position == .top ? .top : .bottom
            config.foreground.spacing = fg.spacing
            config.foreground.horizontalPadding = fg.horizontalPadding
            config.foreground.showClock = fg.showClock
            config.foreground.showBattery = fg.showBattery
            config.foreground.showNetwork = fg.showNetwork
            config.foreground.widgetsBackground.displayed = fg.widgetsBackground.displayed
            config.foreground.widgetsBackground.blur = fg.widgetsBackground.blurRaw

            // Height/Width
            config.foreground.height = convertDimension(fg.height)
            config.foreground.width = convertDimension(fg.width)

            // Background from experimental
            let bg = exp.background
            config.background.enabled = bg.displayed
            config.background.blur = bg.blurRaw
            config.background.height = convertDimension(bg.height)
        }

        // Yabai path
        if let yabai = root.yabai {
            config.yabai.path = yabai.path
        }

        // Aerospace path
        if let aerospace = root.aerospace {
            config.aerospace.path = aerospace.path
        }

        return config
    }

    /// Migrate flat displayed array to zoned layout
    private static func migrateToZonedLayout(displayed: [TomlWidgetItem]) -> ZonedLayout {
        var left: [ZonedWidgetItem] = []
        var center: [ZonedWidgetItem] = []
        var right: [ZonedWidgetItem] = []

        // Special cases: spaces goes left, time goes center, rest goes right
        // Spacers stay within the zone they're in (used to push widgets apart)
        var currentZone: Zone = .left
        var leftOrder = 0
        var centerOrder = 0
        var rightOrder = 0

        for item in displayed {
            let widgetId = item.id
            let definition = WidgetRegistry.widget(for: widgetId)

            // Determine zone based on widget type
            let targetZone: Zone
            if widgetId == "default.spaces" {
                targetZone = .left
            } else if widgetId == "default.time" {
                targetZone = .center
            } else if widgetId == "spacer" {
                // Spacer: if we haven't seen center content yet, it's a left-center divider
                // After spacer, switch to center if we're in left
                if currentZone == .left {
                    currentZone = .center
                    continue // Skip adding spacer, it's just a zone divider
                } else if currentZone == .center {
                    currentZone = .right
                    continue // Skip adding spacer, it's just a zone divider
                }
                targetZone = currentZone
            } else if widgetId == "divider" {
                // Dividers stay in current zone
                targetZone = currentZone
            } else {
                // Use default zone from widget definition, or current zone
                targetZone = definition?.defaultZone ?? currentZone
            }

            // Create zoned widget item
            var inlineConfig: [String: AnyCodableValue]? = nil
            if !item.inlineParams.isEmpty {
                inlineConfig = item.inlineParams.mapValues { AnyCodableValue(from: $0) }
            }

            let priority = definition?.defaultPriority ?? 50

            let zonedItem = ZonedWidgetItem(
                widgetId: widgetId,
                instanceId: UUID(),
                order: 0, // Will be set below
                priority: priority,
                inlineConfig: inlineConfig
            )

            // Add to appropriate zone
            switch targetZone {
            case .left:
                var itemWithOrder = zonedItem
                itemWithOrder.order = leftOrder
                left.append(itemWithOrder)
                leftOrder += 1
            case .center:
                var itemWithOrder = zonedItem
                itemWithOrder.order = centerOrder
                center.append(itemWithOrder)
                centerOrder += 1
            case .right:
                var itemWithOrder = zonedItem
                itemWithOrder.order = rightOrder
                right.append(itemWithOrder)
                rightOrder += 1
            }
        }

        // If migration produced empty zones, use defaults
        if left.isEmpty && center.isEmpty && right.isEmpty {
            return .default
        }

        return ZonedLayout(left: left, center: center, right: right)
    }

    private static func convertDimension(_ dim: BackgroundForegroundHeight) -> BarikConfig.DimensionValue {
        switch dim {
        case .barikDefault: return .barikDefault
        case .menuBar: return .menuBar
        case .float(let v): return .custom(CGFloat(v))
        }
    }
}
