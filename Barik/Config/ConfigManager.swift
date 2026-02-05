import Foundation
import SwiftUI
import TOMLDecoder

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published private(set) var config: BarikConfig = .init()
    @Published private(set) var initError: String?

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
        let homePath = FileManager.default.homeDirectoryForCurrentUser
        let newDirPath = homePath.appendingPathComponent(".config/barik")
        let newPath = newDirPath.appendingPathComponent("config.toml")
        configFilePath = newPath.path

        let legacyPath = homePath.appendingPathComponent(".barik-config.toml")
        let legacyExists = FileManager.default.fileExists(atPath: legacyPath.path)
        let newExists = FileManager.default.fileExists(atPath: newPath.path)

        if legacyExists && newExists {
            let legacyDate = (try? FileManager.default.attributesOfItem(atPath: legacyPath.path)[.modificationDate]) as? Date
            let newDate = (try? FileManager.default.attributesOfItem(atPath: newPath.path)[.modificationDate]) as? Date
            let legacyIsNewer = (legacyDate ?? .distantPast) >= (newDate ?? .distantPast)

            do {
                try FileManager.default.createDirectory(at: newDirPath, withIntermediateDirectories: true)
                if legacyIsNewer {
                    try? FileManager.default.removeItem(at: newPath)
                    try FileManager.default.moveItem(at: legacyPath, to: newPath)
                } else {
                    try? FileManager.default.removeItem(at: legacyPath)
                }
                loadConfig(from: newPath)
            } catch {
                initError = "Error selecting config: \(error.localizedDescription)"
                return
            }
        } else if newExists {
            loadConfig(from: newPath)
        } else if legacyExists {
            do {
                try FileManager.default.createDirectory(at: newDirPath, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: legacyPath, to: newPath)
                loadConfig(from: newPath)
            } catch {
                initError = "Error migrating legacy config: \(error.localizedDescription)"
                return
            }
        } else {
            do {
                try FileManager.default.createDirectory(at: newDirPath, withIntermediateDirectories: true)
                let defaultConfig = BarikConfig()
                try writeConfig(defaultConfig, to: newPath)
                applyConfig(defaultConfig)
            } catch {
                initError = "Error creating default config: \(error.localizedDescription)"
                return
            }
        }

        startWatchingFile(at: newPath.path)
    }

    private func loadConfig(from url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let decoder = TOMLDecoder()
            let decoded = try decoder.decode(BarikConfig.self, from: content)
            applyConfig(decoded)
        } catch {
            print("Error parsing TOML file:", error)
            let defaultConfig = BarikConfig()
            try? writeConfig(defaultConfig, to: url)
            applyConfig(defaultConfig)
            initError = nil
        }
    }

    private func applyConfig(_ newConfig: BarikConfig) {
        let apply = {
            MenuBarAutoHide.setAutoHide(newConfig.foreground.position == .top)
            self.config = newConfig
            if !WidgetGridEngine.shared.isCustomizing {
                WidgetGridEngine.shared.loadFromConfig(newConfig)
            }
            NotificationCenter.default.post(name: Notification.Name("ConfigDidChange"), object: nil)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.sync { apply() }
        }
    }

    private func startWatchingFile(at path: String) {
        fileDescriptor = open(path, O_EVTONLY)
        if fileDescriptor == -1 { return }
        fileWatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor, eventMask: .write,
            queue: DispatchQueue.global())
        fileWatchSource?.setEventHandler { [weak self] in
            guard let self = self, let url = self.configFileURL else { return }
            self.loadConfig(from: url)
        }
        fileWatchSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
            }
        }
        fileWatchSource?.resume()
    }

    private func writeConfig(_ config: BarikConfig, to url: URL) throws {
        let content = ConfigTOMLEncoder.encode(config)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func saveConfig(_ newConfig: BarikConfig) {
        guard let url = configFileURL else { return }
        do {
            try writeConfig(newConfig, to: url)
            applyConfig(newConfig)
        } catch {
            print("Error writing config:", error)
        }
    }

    func updateWidgetOrder(_ widgetIds: [String]) {
        var updated = config
        let existingById = Dictionary(grouping: updated.widgets.displayed, by: { $0.widgetId })
        updated.widgets.displayed = widgetIds.map { widgetId in
            if let item = existingById[widgetId]?.first {
                return item
            }
            return BarikConfig.WidgetItem(widgetId: widgetId)
        }
        saveConfig(updated)
    }

    func updateZonedLayout(left: [ZonedWidgetItem], center: [ZonedWidgetItem], right: [ZonedWidgetItem]) {
        var updated = config
        updated.zonedLayout.left = left
        updated.zonedLayout.center = center
        updated.zonedLayout.right = right
        saveConfig(updated)
    }

    func updateLayout(
        left: [ZonedWidgetItem],
        center: [ZonedWidgetItem],
        right: [ZonedWidgetItem],
        widgetIds: [String]
    ) {
        var updated = config
        updated.zonedLayout.left = left
        updated.zonedLayout.center = center
        updated.zonedLayout.right = right

        let existingById = Dictionary(grouping: updated.widgets.displayed, by: { $0.widgetId })
        updated.widgets.displayed = widgetIds.map { widgetId in
            if let item = existingById[widgetId]?.first {
                return item
            }
            return BarikConfig.WidgetItem(widgetId: widgetId)
        }

        saveConfig(updated)
    }

    func updateConfigValue(key: String, newValue: String) {
        var updated = config
        switch key {
        case "foreground.position":
            if let pos = BarikConfig.ForegroundSettings.Position(rawValue: newValue) {
                updated.foreground.position = pos
            }
        default:
            return
        }
        saveConfig(updated)
    }

    func updateConfigValue(key: String, newValue: Bool) {
        var updated = config
        switch key {
        case "background.enabled":
            updated.background.enabled = newValue
        case "foreground.show-clock":
            updated.foreground.showClock = newValue
        case "foreground.show-battery":
            updated.foreground.showBattery = newValue
        case "foreground.show-network":
            updated.foreground.showNetwork = newValue
        case "foreground.widgets-background.displayed":
            updated.foreground.widgetsBackground.displayed = newValue
        default:
            return
        }
        saveConfig(updated)
    }

    func updateConfigValue(key: String, newValue: Int) {
        var updated = config
        switch key {
        case "background.blur":
            updated.background.blur = newValue
        case "foreground.spacing":
            updated.foreground.spacing = CGFloat(newValue)
        case "foreground.horizontal-padding":
            updated.foreground.horizontalPadding = CGFloat(newValue)
        case "foreground.widgets-background.blur":
            updated.foreground.widgetsBackground.blur = newValue
        default:
            return
        }
        saveConfig(updated)
    }

    func globalWidgetConfig(for widgetId: String) -> ConfigData {
        config.widgets.settings[widgetId]?.values ?? [:]
    }

    func resolvedWidgetConfig(for widgetId: String) -> ConfigData {
        let global = globalWidgetConfig(for: widgetId)
        guard let item = config.widgets.displayed.first(where: { $0.widgetId == widgetId }) else {
            return global
        }
        guard let inline = item.inlineConfig, !inline.isEmpty else {
            return global
        }
        var merged = global
        for (key, value) in inline {
            merged[key] = value
        }
        return merged
    }
}
