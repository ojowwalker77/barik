import AppKit
import Foundation

// MARK: - Now Playing Info (MediaRemote)

/// Strongly-typed model for MediaRemote now playing information
struct NowPlayingInfo: Equatable, Identifiable {
    var id: String { "\(bundleIdentifier ?? "unknown")-\(title)-\(artist)" }

    let bundleIdentifier: String?
    let appName: String?
    let title: String
    let artist: String
    let album: String?
    let artworkData: Data?
    let artworkImage: NSImage?
    let duration: Double?
    let elapsedTime: Double?
    let playbackRate: Double
    let timestamp: Date?
    let uniqueIdentifier: String?

    /// Whether media is currently playing (playback rate > 0)
    var isPlaying: Bool { playbackRate > 0 }

    /// Converts playback rate to PlaybackState
    var state: PlaybackState {
        isPlaying ? .playing : .paused
    }

    // MARK: - Direct Initialization (from MediaRemoteAdapter)

    init(
        bundleIdentifier: String?,
        appName: String?,
        title: String,
        artist: String,
        album: String?,
        artworkData: Data?,
        artworkImage: NSImage?,
        duration: Double?,
        elapsedTime: Double?,
        playbackRate: Double,
        timestamp: Date?,
        uniqueIdentifier: String?
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.artworkImage = artworkImage
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.playbackRate = playbackRate
        self.timestamp = timestamp
        self.uniqueIdentifier = uniqueIdentifier
    }

    // MARK: - Initialization from MediaRemote Dictionary

    init(
        from info: [String: Any],
        bundleIdentifier: String? = nil,
        appName: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName

        // Extract basic metadata
        self.title = info[MRNowPlayingInfoKey.title] as? String ?? "Unknown"
        self.artist = info[MRNowPlayingInfoKey.artist] as? String ?? "Unknown"
        self.album = info[MRNowPlayingInfoKey.album] as? String

        // Extract timing info
        self.duration = info[MRNowPlayingInfoKey.duration] as? Double
        self.elapsedTime = info[MRNowPlayingInfoKey.elapsedTime] as? Double
        self.playbackRate = info[MRNowPlayingInfoKey.playbackRate] as? Double ?? 0

        // Extract timestamp
        if let timestamp = info[MRNowPlayingInfoKey.timestamp] as? Double {
            self.timestamp = Date(timeIntervalSince1970: timestamp)
        } else {
            self.timestamp = nil
        }

        // Extract unique identifier
        self.uniqueIdentifier = info[MRNowPlayingInfoKey.uniqueIdentifier] as? String
            ?? info[MRNowPlayingInfoKey.contentItemIdentifier] as? String

        // Extract artwork data and convert to NSImage
        if let artworkData = info[MRNowPlayingInfoKey.artworkData] as? Data {
            self.artworkData = artworkData
            self.artworkImage = NSImage(data: artworkData)
        } else {
            self.artworkData = nil
            self.artworkImage = nil
        }
    }

    // MARK: - Empty/Default State

    /// Creates an empty info representing no media playing
    static var empty: NowPlayingInfo {
        NowPlayingInfo(from: [:])
    }

    /// Whether this represents actual media or is empty
    var isEmpty: Bool {
        title == "Unknown" && artist == "Unknown"
    }

    // MARK: - Equatable

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier &&
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.playbackRate == rhs.playbackRate &&
        lhs.uniqueIdentifier == rhs.uniqueIdentifier
        // Note: Don't compare artworkData for performance (it's large)
        // Note: Don't compare elapsedTime as it changes constantly
    }
}
