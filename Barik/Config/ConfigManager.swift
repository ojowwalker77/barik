import Foundation
import SwiftUI
import TOMLDecoder

struct ConfigLoadError: Equatable {
    let path: String
    let message: String
}

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published private(set) var config: BarikConfig = .init()
    @Published private(set) var lastValidConfig: BarikConfig?
    @Published private(set) var configLoadError: ConfigLoadError?
    @Published private(set) var initError: String?

    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var configFilePath: String?
    private var configDirectoryPath: String?
    private var reloadWorkItem: DispatchWorkItem?
    private var lastLoadedConfigContents: String?

    var configFileURL: URL? {
        guard let path = configFilePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var configFilePathForDisplay: String {
        configFilePath ?? "~/.config/barik/config.toml"
    }

    private init() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser
        let newDirURL = homePath.appendingPathComponent(".config/barik")
        let newFileURL = newDirURL.appendingPathComponent("config.toml")
        let legacyURL = homePath.appendingPathComponent(".barik-config.toml")

        configDirectoryPath = newDirURL.path
        configFilePath = newFileURL.path

        do {
            try migrateLegacyConfigIfNeeded(from: legacyURL, to: newFileURL, directory: newDirURL)
            try ensureConfigDirectoryExists(at: newDirURL)
            if FileManager.default.fileExists(atPath: newFileURL.path) {
                reloadConfigFromDisk()
            } else {
                let defaultConfig = BarikConfig()
                try writeConfig(defaultConfig, to: newFileURL)
                applyRuntimeConfig(defaultConfig, rememberAsLastValid: true)
            }
        } catch {
            initError = error.localizedDescription
            applyRuntimeConfig(.init(), rememberAsLastValid: false)
        }

        if let directoryPath = configDirectoryPath {
            startWatchingConfigDirectory(at: directoryPath)
        }
    }

    private func migrateLegacyConfigIfNeeded(from legacyURL: URL, to newURL: URL, directory: URL) throws {
        let fileManager = FileManager.default
        let legacyExists = fileManager.fileExists(atPath: legacyURL.path)
        let newExists = fileManager.fileExists(atPath: newURL.path)

        guard legacyExists else { return }

        try ensureConfigDirectoryExists(at: directory)

        if newExists {
            let legacyDate = (try? fileManager.attributesOfItem(atPath: legacyURL.path)[.modificationDate]) as? Date
            let newDate = (try? fileManager.attributesOfItem(atPath: newURL.path)[.modificationDate]) as? Date
            let useLegacy = (legacyDate ?? .distantPast) >= (newDate ?? .distantPast)

            if useLegacy {
                try? fileManager.removeItem(at: newURL)
                try fileManager.moveItem(at: legacyURL, to: newURL)
            } else {
                try? fileManager.removeItem(at: legacyURL)
            }
        } else {
            try fileManager.moveItem(at: legacyURL, to: newURL)
        }
    }

    private func ensureConfigDirectoryExists(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    private func validatedConfig(from content: String) throws -> BarikConfig {
        try Self.decodeConfig(contents: content)
    }

    static func decodeConfig(contents: String) throws -> BarikConfig {
        try TOMLDecoder().decode(BarikConfig.self, from: contents)
    }

    static func shouldReloadConfig(contents: String, lastLoadedContents: String?, hasActiveLoadError: Bool) -> Bool {
        contents != lastLoadedContents || hasActiveLoadError
    }

    private func reloadConfigFromDisk() {
        guard let url = configFileURL else { return }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let hasActiveLoadError = configLoadError != nil
            guard Self.shouldReloadConfig(
                contents: content,
                lastLoadedContents: lastLoadedConfigContents,
                hasActiveLoadError: hasActiveLoadError
            ) else {
                return
            }
            let validated = try validatedConfig(from: content)
            lastLoadedConfigContents = content
            applyRuntimeConfig(validated, rememberAsLastValid: true)
            clearConfigError()
        } catch {
            handleConfigLoadFailure(error, path: url.path)
        }
    }

    private func handleConfigLoadFailure(_ error: Error, path: String) {
        let loadError = ConfigLoadError(path: path, message: error.localizedDescription)
        DispatchQueue.main.async {
            self.configLoadError = loadError
            AppDiagnostics.shared.post(
                id: "config-load-error",
                kind: .config,
                title: "Config Error",
                message: "\(loadError.path)\n\(loadError.message)"
            )

            let fallback = self.lastValidConfig ?? BarikConfig()
            self.applyRuntimeConfig(fallback, rememberAsLastValid: false)
        }
    }

    private func clearConfigError() {
        DispatchQueue.main.async {
            self.configLoadError = nil
            AppDiagnostics.shared.clear(id: "config-load-error")
        }
    }

    private func applyRuntimeConfig(_ newConfig: BarikConfig, rememberAsLastValid: Bool) {
        let apply = {
            if newConfig.system.manageMenuBarAutohide {
                MenuBarAutoHide.setAutoHide(newConfig.foreground.position == .top)
            }

            self.config = newConfig
            if rememberAsLastValid {
                self.lastValidConfig = newConfig
            }
            if !WidgetGridEngine.shared.isCustomizing {
                WidgetGridEngine.shared.loadFromConfig(newConfig)
            }
            NotificationCenter.default.post(name: Notification.Name("ConfigDidChange"), object: nil)
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func startWatchingConfigDirectory(at path: String) {
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }

        fileWatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )
        fileWatchSource?.setEventHandler { [weak self] in
            self?.scheduleReloadFromDisk()
        }
        fileWatchSource?.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor != -1 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        fileWatchSource?.resume()
    }

    private func scheduleReloadFromDisk() {
        reloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reloadConfigFromDisk()
        }
        reloadWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func writeConfig(_ config: BarikConfig, to url: URL) throws {
        let content = ConfigTOMLEncoder.encode(config)
        try content.write(to: url, atomically: true, encoding: .utf8)
        lastLoadedConfigContents = content
    }

    private func saveConfig(_ newConfig: BarikConfig) {
        guard let url = configFileURL else { return }

        do {
            try writeConfig(newConfig, to: url)
            applyRuntimeConfig(newConfig, rememberAsLastValid: true)
            clearConfigError()
        } catch {
            AppDiagnostics.shared.post(
                id: "config-save-error",
                kind: .config,
                title: "Config Save Error",
                message: error.localizedDescription
            )
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
        case "system.manage-menu-bar-autohide":
            updated.system.manageMenuBarAutohide = newValue
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
