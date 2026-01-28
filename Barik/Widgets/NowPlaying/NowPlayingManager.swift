import AppKit
import Combine
import Foundation

// MARK: - Playback State

/// Represents the current playback state.
enum PlaybackState: String {
    case playing, paused, stopped
}

// MARK: - Now Playing Song Model

/// A model representing the currently playing song.
struct NowPlayingSong: Equatable, Identifiable {
    var id: String { title + artist }
    let appName: String
    let bundleIdentifier: String?
    let state: PlaybackState
    let title: String
    let artist: String
    let albumArtURL: URL?
    let albumArtImage: NSImage?  // For MediaRemote (preferred)
    let position: Double?
    let duration: Double?

    // MARK: - Initialize from MediaRemote NowPlayingInfo

    init(from info: NowPlayingInfo) {
        self.appName = info.appName ?? "Unknown"
        self.bundleIdentifier = info.bundleIdentifier
        self.state = info.state
        self.title = info.title
        self.artist = info.artist
        self.albumArtURL = nil  // MediaRemote uses image data, not URLs
        self.albumArtImage = info.artworkImage
        self.position = info.elapsedTime
        self.duration = info.duration
    }

    // MARK: - Initialize from AppleScript Output (Fallback)

    /// Initializes a song model from a given output string.
    /// - Parameters:
    ///   - application: The name of the music application.
    ///   - output: The output string returned by AppleScript.
    init?(application: String, from output: String) {
        let components = output.components(separatedBy: "|")
        guard components.count == 6,
            let state = PlaybackState(rawValue: components[0])
        else {
            return nil
        }
        // Replace commas with dots for correct decimal conversion.
        let positionString = components[4].replacingOccurrences(
            of: ",", with: ".")
        let durationString = components[5].replacingOccurrences(
            of: ",", with: ".")
        guard let position = Double(positionString),
            let duration = Double(durationString)
        else {
            return nil
        }

        self.appName = application
        self.bundleIdentifier = nil
        self.state = state
        self.title = components[1]
        self.artist = components[2]
        self.albumArtURL = URL(string: components[3])
        self.albumArtImage = nil  // AppleScript uses URLs, not image data
        self.position = position
        if application == MusicApp.spotify.rawValue {
            self.duration = duration / 1000
        } else {
            self.duration = duration
        }
    }

    // MARK: - Equatable

    static func == (lhs: NowPlayingSong, rhs: NowPlayingSong) -> Bool {
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.state == rhs.state &&
        lhs.appName == rhs.appName
        // Note: Don't compare position as it changes constantly
        // Note: Don't compare albumArtImage for performance
    }
}

// MARK: - Supported Music Applications

/// Supported music applications with corresponding AppleScript commands.
enum MusicApp: String, CaseIterable {
    case spotify = "Spotify"
    case music = "Music"

    /// Bundle identifiers for each app (used for safe running check).
    var bundleIdentifier: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }

    /// AppleScript to fetch the now playing song.
    /// Note: Does NOT include "if application is running" check - caller must verify first.
    var nowPlayingScript: String {
        if self == .music {
            return """
                tell application "Music"
                    try
                        if player state is playing or player state is paused then
                            set currentTrack to current track
                            try
                                set artworkURL to (get URL of artwork 1 of currentTrack) as text
                            on error
                                set artworkURL to ""
                            end try
                            set stateText to ""
                            if player state is playing then
                                set stateText to "playing"
                            else if player state is paused then
                                set stateText to "paused"
                            end if
                            return stateText & "|" & (name of currentTrack) & "|" & (artist of currentTrack) & "|" & artworkURL & "|" & (player position as text) & "|" & ((duration of currentTrack) as text)
                        else
                            return "stopped"
                        end if
                    on error
                        return "stopped"
                    end try
                end tell
                """
        } else {
            return """
                tell application "\(rawValue)"
                    try
                        if player state is playing then
                            set currentTrack to current track
                            return "playing|" & (name of currentTrack) & "|" & (artist of currentTrack) & "|" & (artwork url of currentTrack) & "|" & player position & "|" & (duration of currentTrack)
                        else if player state is paused then
                            set currentTrack to current track
                            return "paused|" & (name of currentTrack) & "|" & (artist of currentTrack) & "|" & (artwork url of currentTrack) & "|" & player position & "|" & (duration of currentTrack)
                        else
                            return "stopped"
                        end if
                    on error
                        return "stopped"
                    end try
                end tell
                """
        }
    }

    var previousTrackCommand: String {
        "tell application \"\(rawValue)\" to previous track"
    }

    var togglePlayPauseCommand: String {
        "tell application \"\(rawValue)\" to playpause"
    }

    var nextTrackCommand: String {
        "tell application \"\(rawValue)\" to next track"
    }
}

// MARK: - Now Playing Provider

/// Provides functionality to fetch the now playing song and execute playback commands via AppleScript.
final class NowPlayingProvider {

    /// Returns the current playing song from any supported music application.
    static func fetchNowPlaying() -> NowPlayingSong? {
        for app in MusicApp.allCases {
            if let song = fetchNowPlaying(from: app) {
                return song
            }
        }
        return nil
    }

    /// Returns the now playing song for a specific music application.
    private static func fetchNowPlaying(from app: MusicApp) -> NowPlayingSong? {
        // Check if app is running BEFORE calling AppleScript to avoid "Where is X?" dialog
        guard isAppRunning(app) else { return nil }
        guard let output = runAppleScript(app.nowPlayingScript),
            output != "stopped"
        else {
            return nil
        }
        return NowPlayingSong(application: app.rawValue, from: output)
    }

    /// Checks if the specified music application is currently running using bundle identifier.
    /// Uses NSWorkspace to avoid triggering "Where is X?" dialogs.
    static func isAppRunning(_ app: MusicApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == app.bundleIdentifier
        }
    }

    /// Executes the provided AppleScript and returns the trimmed result.
    @discardableResult
    static func runAppleScript(_ script: String) -> String? {
        guard let appleScript = NSAppleScript(source: script) else {
            return nil
        }
        var error: NSDictionary?
        let outputDescriptor = appleScript.executeAndReturnError(&error)
        if let error = error {
            print("AppleScript Error: \(error)")
            return nil
        }
        return outputDescriptor.stringValue?.trimmingCharacters(
            in: .whitespacesAndNewlines)
    }

    /// Returns the first running music application.
    static func activeMusicApp() -> MusicApp? {
        MusicApp.allCases.first { isAppRunning($0) }
    }

    /// Executes a playback command for the active music application.
    static func executeCommand(_ command: (MusicApp) -> String) {
        guard let activeApp = activeMusicApp() else { return }
        _ = runAppleScript(command(activeApp))
    }
}

// MARK: - Now Playing Manager

/// An observable manager that provides now playing information.
/// Uses MediaRemote (notification-based) when available, falls back to AppleScript polling.
final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    @Published private(set) var nowPlaying: NowPlayingSong?

    private let mediaRemote = MediaRemoteService.shared
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: AnyCancellable?

    /// Whether we're using MediaRemote (true) or AppleScript fallback (false)
    var isUsingMediaRemote: Bool { mediaRemote.isAvailable }

    private init() {
        if mediaRemote.isAvailable {
            // Use notification-based MediaRemote (efficient!)
            setupMediaRemoteBinding()
        } else {
            // Fall back to polling AppleScript
            startAppleScriptPolling()
        }
    }

    // MARK: - MediaRemote Mode

    private func setupMediaRemoteBinding() {
        mediaRemote.$nowPlaying
            .receive(on: DispatchQueue.main)
            .map { info -> NowPlayingSong? in
                guard let info = info else { return nil }
                return NowPlayingSong(from: info)
            }
            .assign(to: &$nowPlaying)
    }

    // MARK: - AppleScript Fallback Mode

    private func startAppleScriptPolling() {
        pollTimer = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchViaAppleScript()
            }
    }

    private func fetchViaAppleScript() {
        DispatchQueue.global(qos: .background).async {
            let song = NowPlayingProvider.fetchNowPlaying()
            DispatchQueue.main.async { [weak self] in
                self?.nowPlaying = song
            }
        }
    }

    // MARK: - Playback Commands

    /// Skips to the previous track.
    func previousTrack() {
        if mediaRemote.isAvailable {
            mediaRemote.previousTrack()
        } else {
            NowPlayingProvider.executeCommand { $0.previousTrackCommand }
        }
    }

    /// Toggles between play and pause.
    func togglePlayPause() {
        if mediaRemote.isAvailable {
            mediaRemote.togglePlayPause()
        } else {
            NowPlayingProvider.executeCommand { $0.togglePlayPauseCommand }
        }
    }

    /// Skips to the next track.
    func nextTrack() {
        if mediaRemote.isAvailable {
            mediaRemote.nextTrack()
        } else {
            NowPlayingProvider.executeCommand { $0.nextTrackCommand }
        }
    }
}
