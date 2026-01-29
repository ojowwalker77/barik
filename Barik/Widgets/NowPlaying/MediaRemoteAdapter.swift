import AppKit
import Combine
import Foundation

// MARK: - MediaRemote Adapter

/// Wrapper for mediaremote-adapter Perl script that provides universal media detection
/// Works on macOS 15.4+ by using /usr/bin/perl's com.apple.perl5 bundle ID
final class MediaRemoteAdapter: ObservableObject {

    // MARK: - Published State

    @Published private(set) var nowPlaying: NowPlayingInfo?
    @Published private(set) var isRunning = false

    // MARK: - Private Properties

    private var streamProcess: Process?
    private var outputPipe: Pipe?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "com.barik.mediaremote-adapter", qos: .userInitiated)

    private var appNameCache: [String: String] = [:]

    private var perlPath: String { "/usr/bin/perl" }

    private var scriptPath: String? {
        // Script is copied to Resources root by Xcode file sync
        Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl")
    }

    private var frameworkPath: String? {
        // Framework is copied to Resources by build script
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let path = (resourcePath as NSString).appendingPathComponent("MediaRemoteAdapter.framework")
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    // MARK: - Initialization

    init() {}

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Starts the streaming process for real-time media updates
    func start() {
        guard !isRunning else { return }
        guard let scriptPath = scriptPath, let frameworkPath = frameworkPath else {
            print("[MediaRemoteAdapter] Missing script or framework in bundle")
            return
        }

        queue.async { [weak self] in
            self?.startStreamProcess(scriptPath: scriptPath, frameworkPath: frameworkPath)
        }
    }

    /// Stops the streaming process
    func stop() {
        streamProcess?.terminate()
        streamProcess = nil
        outputPipe = nil
        isRunning = false
    }

    // MARK: - Commands

    /// Sends a playback command (play, pause, togglePlayPause, nextTrack, previousTrack, etc.)
    func sendCommand(_ command: String) {
        guard let scriptPath = scriptPath, let frameworkPath = frameworkPath else { return }

        queue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [scriptPath, frameworkPath, "send", command]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("[MediaRemoteAdapter] Command failed: \(error)")
            }
        }
    }

    // MARK: - Convenience Commands

    func togglePlayPause() { sendCommand("togglePlayPause") }
    func play() { sendCommand("play") }
    func pause() { sendCommand("pause") }
    func nextTrack() { sendCommand("nextTrack") }
    func previousTrack() { sendCommand("previousTrack") }

    // MARK: - Private Methods

    private func startStreamProcess(scriptPath: String, frameworkPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: perlPath)
        process.arguments = [scriptPath, frameworkPath, "stream", "--no-diff"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // Handle output data
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleOutputData(data)
        }

        // Handle process termination
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                // Auto-restart if terminated unexpectedly
                self?.scheduleRestart()
            }
        }

        do {
            try process.run()
            self.streamProcess = process
            self.outputPipe = pipe
            DispatchQueue.main.async {
                self.isRunning = true
            }
        } catch {
            print("[MediaRemoteAdapter] Failed to start: \(error)")
        }
    }

    private func handleOutputData(_ data: Data) {
        buffer.append(data)

        // Process complete JSON lines (newline-delimited)
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeFirst(newlineIndex + 1 - buffer.startIndex)

            if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
               let payload = json["payload"] as? [String: Any] {
                let info = parseNowPlayingInfo(from: payload)
                DispatchQueue.main.async { [weak self] in
                    self?.nowPlaying = info
                }
            }
        }
    }

    private func parseNowPlayingInfo(from json: [String: Any]) -> NowPlayingInfo? {
        // Check if there's meaningful data
        guard let title = json["title"] as? String else {
            return nil
        }

        let bundleId = json["bundleIdentifier"] as? String
        let artist = json["artist"] as? String ?? "Unknown"
        let album = json["album"] as? String
        let playing = json["playing"] as? Bool ?? false
        let duration = json["duration"] as? Double
        let elapsedTime = json["elapsedTime"] as? Double
        let playbackRate = json["playbackRate"] as? Double ?? (playing ? 1.0 : 0.0)

        // Parse artwork data (base64 encoded)
        var artworkData: Data?
        var artworkImage: NSImage?
        if let artworkBase64 = json["artworkData"] as? String {
            artworkData = Data(base64Encoded: artworkBase64)
            if let data = artworkData {
                artworkImage = NSImage(data: data)
            }
        }

        // Get app display name
        var appName: String?
        if let bundleId = bundleId {
            appName = getAppName(for: bundleId)
        }

        return NowPlayingInfo(
            bundleIdentifier: bundleId,
            appName: appName,
            title: title,
            artist: artist,
            album: album,
            artworkData: artworkData,
            artworkImage: artworkImage,
            duration: duration,
            elapsedTime: elapsedTime,
            playbackRate: playbackRate,
            timestamp: Date(),
            uniqueIdentifier: json["uniqueIdentifier"] as? String
                ?? (json["uniqueIdentifier"] as? NSNumber).map { String($0.int64Value) }
        )
    }

    private func getAppName(for bundleId: String) -> String? {
        if let cached = appNameCache[bundleId] {
            return cached
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: appURL.path)
        appNameCache[bundleId] = name
        return name
    }

    private func scheduleRestart() {
        // Restart after a short delay if we were running
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.start()
        }
    }

    // MARK: - One-shot Fetch

    /// Fetches current now playing info once (useful for initial state)
    func fetchOnce(completion: @escaping (NowPlayingInfo?) -> Void) {
        guard let scriptPath = scriptPath, let frameworkPath = frameworkPath else {
            completion(nil)
            return
        }

        queue.async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [scriptPath, frameworkPath, "get"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let info = self?.parseNowPlayingInfo(from: json)
                    DispatchQueue.main.async {
                        completion(info)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            } catch {
                print("[MediaRemoteAdapter] Fetch failed: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}
