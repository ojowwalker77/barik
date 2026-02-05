import AppKit
import Combine
import Foundation

class SpacesViewModel: ObservableObject {
    @Published var spaces: [AnySpace] = []
    private var timer: Timer?
    private var provider: AnySpacesProvider?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastStateSignature: String = ""
    var monitorName: String?

    init(monitorName: String? = nil) {
        self.monitorName = monitorName
        let runningApps = NSWorkspace.shared.runningApplications.compactMap {
            $0.localizedName?.lowercased()
        }
        if runningApps.contains("yabai") {
            provider = AnySpacesProvider(YabaiSpacesProvider())
        } else if runningApps.contains("aerospace") {
            provider = AnySpacesProvider(AerospaceSpacesProvider())
        } else {
            provider = nil
        }
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        // Event-driven: instant updates for app/space changes
        let workspace = NSWorkspace.shared

        // App activated (window focus changed)
        let appObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.loadSpaces()
        }
        workspaceObservers.append(appObserver)

        // Space changed (macOS native notification)
        let spaceObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.loadSpaces()
        }
        workspaceObservers.append(spaceObserver)

        // Fast polling with change detection (yabai/aerospace don't trigger NSWorkspace notifications)
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) {
            [weak self] _ in
            self?.loadSpaces()
        }
        loadSpaces()
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    private func loadSpaces() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let provider = self.provider,
                let spaces = provider.getSpacesWithWindows()
            else {
                DispatchQueue.main.async {
                    if !self.spaces.isEmpty {
                        self.spaces = []
                    }
                }
                return
            }
            let sortedSpaces = spaces.sorted { $0.id < $1.id }
            var filteredSpaces = sortedSpaces
            if let monitor = self.monitorName {
                filteredSpaces = sortedSpaces.filter { $0.monitor == monitor }
            }

            // Change detection: only update UI if state actually changed
            let signature = self.computeSignature(filteredSpaces)
            guard signature != self.lastStateSignature else { return }

            DispatchQueue.main.async {
                self.lastStateSignature = signature
                self.spaces = filteredSpaces
            }
        }
    }

    /// Compute a signature of the current state to detect changes
    private func computeSignature(_ spaces: [AnySpace]) -> String {
        spaces.map { space in
            let windowIds = space.windows.map { "\($0.id):\($0.isFocused)" }.joined(separator: ",")
            return "\(space.id):\(space.isFocused):[\(windowIds)]"
        }.joined(separator: "|")
    }

    func switchToSpace(_ space: AnySpace, needWindowFocus: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusSpace(
                spaceId: space.id, needWindowFocus: needWindowFocus)
        }
    }

    func switchToWindow(_ window: AnyWindow) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusWindow(windowId: String(window.id))
        }
    }
}

class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() {}
    func icon(for appName: String) -> NSImage? {
        if let cached = cache.object(forKey: appName as NSString) {
            return cached
        }
        let workspace = NSWorkspace.shared
        if let app = workspace.runningApplications.first(where: {
            $0.localizedName == appName
        }),
            let bundleURL = app.bundleURL
        {
            let icon = workspace.icon(forFile: bundleURL.path)
            cache.setObject(icon, forKey: appName as NSString)
            return icon
        }
        return nil
    }
}
