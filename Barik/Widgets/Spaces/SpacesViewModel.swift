import AppKit
import Combine
import Foundation

final class SpacesStore: ObservableObject {
    static let shared = SpacesStore()

    @Published private(set) var spaces: [AnySpace] = []

    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private let refreshQueue = DispatchQueue(label: "Barik.SpacesStore", qos: .userInitiated)
    private var isRefreshing = false
    private var hasPendingRefresh = false
    private var lastStateSignature = ""

    private init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    static func filterSpaces(_ spaces: [AnySpace], monitorName: String?) -> [AnySpace] {
        guard let monitorName else { return spaces }
        return spaces.filter { $0.monitor == nil || $0.monitor == monitorName }
    }

    func spaces(for displayID: CGDirectDisplayID?) -> [AnySpace] {
        guard let displayID, let monitorName = NSScreen.screen(with: displayID)?.localizedName else {
            return spaces
        }

        return Self.filterSpaces(spaces, monitorName: monitorName)
    }

    func switchToSpace(_ space: AnySpace, needWindowFocus: Bool = false) {
        refreshQueue.async {
            self.currentProvider()?.focusSpace(spaceId: space.id, needWindowFocus: needWindowFocus)
            self.requestRefresh()
        }
    }

    func switchToWindow(_ window: AnyWindow, in space: AnySpace) {
        refreshQueue.async {
            let provider = self.currentProvider()
            provider?.focusSpace(spaceId: space.id, needWindowFocus: false)
            self.refreshQueue.asyncAfter(deadline: .now() + 0.1) {
                provider?.focusWindow(windowId: String(window.id))
                self.requestRefresh()
            }
        }
    }

    func requestRefresh() {
        refreshQueue.async {
            if self.isRefreshing {
                self.hasPendingRefresh = true
                return
            }
            self.performRefresh()
        }
    }

    private func startMonitoring() {
        let workspace = NSWorkspace.shared

        let appObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestRefresh()
        }
        workspaceObservers.append(appObserver)

        let spaceObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestRefresh()
        }
        workspaceObservers.append(spaceObserver)

        updatePollingState()
        requestRefresh()
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    private func updatePollingState() {
        let shouldPoll = currentProvider() != nil
        DispatchQueue.main.async {
            if shouldPoll, self.timer == nil {
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
                    self?.requestRefresh()
                }
            } else if !shouldPoll, self.timer != nil {
                self.timer?.invalidate()
                self.timer = nil
            }
        }
    }

    private func performRefresh() {
        isRefreshing = true
        let provider = currentProvider()

        guard let provider, let freshSpaces = provider.getSpacesWithWindows() else {
            DispatchQueue.main.async {
                self.updateSpacesIfNeeded([])
            }
            finishRefresh()
            return
        }

        let sortedSpaces = freshSpaces.sorted { $0.id < $1.id }
        DispatchQueue.main.async {
            self.updateSpacesIfNeeded(sortedSpaces)
        }
        finishRefresh()
    }

    private func finishRefresh() {
        refreshQueue.async {
            self.isRefreshing = false
            self.updatePollingState()
            if self.hasPendingRefresh {
                self.hasPendingRefresh = false
                self.performRefresh()
            }
        }
    }

    private func updateSpacesIfNeeded(_ newSpaces: [AnySpace]) {
        let signature = computeSignature(newSpaces)
        guard signature != lastStateSignature else { return }
        lastStateSignature = signature
        spaces = newSpaces
    }

    private func computeSignature(_ spaces: [AnySpace]) -> String {
        spaces.map { space in
            let windowIds = space.windows.map { "\($0.id):\($0.isFocused)" }.joined(separator: ",")
            return "\(space.id):\(space.isFocused):\(space.monitor ?? ""):[\(windowIds)]"
        }.joined(separator: "|")
    }

    private func currentProvider() -> AnySpacesProvider? {
        let runningApps = NSWorkspace.shared.runningApplications.compactMap { $0.localizedName?.lowercased() }
        if runningApps.contains("yabai") {
            return AnySpacesProvider(YabaiSpacesProvider())
        }
        if runningApps.contains("aerospace") {
            return AnySpacesProvider(AerospaceSpacesProvider())
        }
        return nil
    }
}

typealias SpacesViewModel = SpacesStore

class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {}

    func icon(for appName: String) -> NSImage? {
        if let cached = cache.object(forKey: appName as NSString) {
            return cached
        }

        let workspace = NSWorkspace.shared
        if let app = workspace.runningApplications.first(where: { $0.localizedName == appName }),
           let bundleURL = app.bundleURL {
            let icon = workspace.icon(forFile: bundleURL.path)
            cache.setObject(icon, forKey: appName as NSString)
            return icon
        }
        return nil
    }
}
