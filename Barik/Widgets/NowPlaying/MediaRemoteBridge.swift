import Foundation

// MARK: - MediaRemote Command Types

/// Commands that can be sent to media players via MediaRemote
enum MRCommand: UInt32 {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
    case advanceShuffleMode = 6
    case advanceRepeatMode = 7
    case beginFastForward = 8
    case endFastForward = 9
    case beginRewind = 10
    case endRewind = 11
    case rewind15Seconds = 12
    case fastForward15Seconds = 13
    case rewind30Seconds = 14
    case fastForward30Seconds = 15
    case skipForward = 17
    case skipBackward = 18
    case changePlaybackRate = 19
    case rateTrack = 20
    case likeTrack = 21
    case dislikeTrack = 22
    case bookmarkTrack = 23
    case seekToPlaybackPosition = 45
}

// MARK: - MediaRemote Info Keys

/// Keys for extracting information from MediaRemote's now playing info dictionary
enum MRNowPlayingInfoKey {
    static let title = "kMRMediaRemoteNowPlayingInfoTitle"
    static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
    static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
    static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
    static let artworkMIMEType = "kMRMediaRemoteNowPlayingInfoArtworkMIMEType"
    static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
    static let elapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
    static let playbackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    static let timestamp = "kMRMediaRemoteNowPlayingInfoTimestamp"
    static let uniqueIdentifier = "kMRMediaRemoteNowPlayingInfoUniqueIdentifier"
    static let contentItemIdentifier = "kMRMediaRemoteNowPlayingInfoContentItemIdentifier"
}

// MARK: - MediaRemote Notification Names

/// Notification names for MediaRemote events
enum MRNotification {
    static let nowPlayingInfoDidChange = "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
    static let nowPlayingApplicationIsPlayingDidChange = "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
    static let nowPlayingApplicationDidChange = "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
}

// MARK: - MediaRemote Bridge

/// Bridge to the private MediaRemote.framework for universal media control
/// Uses dynamic loading to avoid linking issues
final class MediaRemoteBridge {

    // MARK: - Type Aliases for Function Pointers

    private typealias MRMediaRemoteGetNowPlayingInfoFunc = @convention(c) (
        DispatchQueue,
        @escaping ([String: Any]) -> Void
    ) -> Void

    private typealias MRMediaRemoteGetNowPlayingClientFunc = @convention(c) (
        DispatchQueue,
        @escaping (AnyObject?) -> Void
    ) -> Void

    private typealias MRMediaRemoteGetNowPlayingApplicationIsPlayingFunc = @convention(c) (
        DispatchQueue,
        @escaping (Bool) -> Void
    ) -> Void

    private typealias MRMediaRemoteRegisterForNowPlayingNotificationsFunc = @convention(c) (
        DispatchQueue
    ) -> Void

    private typealias MRMediaRemoteUnregisterForNowPlayingNotificationsFunc = @convention(c) () -> Void

    private typealias MRMediaRemoteSendCommandFunc = @convention(c) (
        UInt32,  // MRCommand
        CFDictionary?  // options
    ) -> Bool

    private typealias MRNowPlayingClientGetBundleIdentifierFunc = @convention(c) (
        AnyObject?
    ) -> CFString?

    private typealias MRNowPlayingClientGetDisplayNameFunc = @convention(c) (
        AnyObject?
    ) -> CFString?

    // MARK: - Function Pointers

    private let getNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFunc?
    private let getNowPlayingClient: MRMediaRemoteGetNowPlayingClientFunc?
    private let getNowPlayingApplicationIsPlaying: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunc?
    private let registerForNowPlayingNotifications: MRMediaRemoteRegisterForNowPlayingNotificationsFunc?
    private let unregisterForNowPlayingNotifications: MRMediaRemoteUnregisterForNowPlayingNotificationsFunc?
    private let sendCommand: MRMediaRemoteSendCommandFunc?
    private let clientGetBundleIdentifier: MRNowPlayingClientGetBundleIdentifierFunc?
    private let clientGetDisplayName: MRNowPlayingClientGetDisplayNameFunc?

    // MARK: - Properties

    private let bundle: CFBundle?
    let isAvailable: Bool

    // MARK: - Initialization

    init?() {
        let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework"

        guard let frameworkURL = CFURLCreateWithFileSystemPath(
            kCFAllocatorDefault,
            frameworkPath as CFString,
            .cfurlposixPathStyle,
            true
        ) else {
            self.bundle = nil
            self.isAvailable = false
            self.getNowPlayingInfo = nil
            self.getNowPlayingClient = nil
            self.getNowPlayingApplicationIsPlaying = nil
            self.registerForNowPlayingNotifications = nil
            self.unregisterForNowPlayingNotifications = nil
            self.sendCommand = nil
            self.clientGetBundleIdentifier = nil
            self.clientGetDisplayName = nil
            return nil
        }

        guard let bundle = CFBundleCreate(kCFAllocatorDefault, frameworkURL) else {
            self.bundle = nil
            self.isAvailable = false
            self.getNowPlayingInfo = nil
            self.getNowPlayingClient = nil
            self.getNowPlayingApplicationIsPlaying = nil
            self.registerForNowPlayingNotifications = nil
            self.unregisterForNowPlayingNotifications = nil
            self.sendCommand = nil
            self.clientGetBundleIdentifier = nil
            self.clientGetDisplayName = nil
            return nil
        }

        self.bundle = bundle

        // Load function pointers
        self.getNowPlayingInfo = Self.loadFunction(
            from: bundle,
            name: "MRMediaRemoteGetNowPlayingInfo"
        )

        self.getNowPlayingClient = Self.loadFunction(
            from: bundle,
            name: "MRMediaRemoteGetNowPlayingClient"
        )

        self.getNowPlayingApplicationIsPlaying = Self.loadFunction(
            from: bundle,
            name: "MRMediaRemoteGetNowPlayingApplicationIsPlaying"
        )

        self.registerForNowPlayingNotifications = Self.loadFunction(
            from: bundle,
            name: "MRMediaRemoteRegisterForNowPlayingNotifications"
        )

        self.unregisterForNowPlayingNotifications = Self.loadFunction(
            from: bundle,
            name: "MRMediaRemoteUnregisterForNowPlayingNotifications"
        )

        self.sendCommand = Self.loadFunction(
            from: bundle,
            name: "MRMediaRemoteSendCommand"
        )

        self.clientGetBundleIdentifier = Self.loadFunction(
            from: bundle,
            name: "MRNowPlayingClientGetBundleIdentifier"
        )

        self.clientGetDisplayName = Self.loadFunction(
            from: bundle,
            name: "MRNowPlayingClientGetDisplayName"
        )

        // Consider available if we can at least get now playing info
        self.isAvailable = getNowPlayingInfo != nil

        if !isAvailable {
            return nil
        }
    }

    // MARK: - Private Helpers

    private static func loadFunction<T>(from bundle: CFBundle, name: String) -> T? {
        guard let pointer = CFBundleGetFunctionPointerForName(bundle, name as CFString) else {
            return nil
        }
        return unsafeBitCast(pointer, to: T.self)
    }

    // MARK: - Public API

    /// Fetches the current now playing information
    func fetchNowPlayingInfo(completion: @escaping ([String: Any]) -> Void) {
        guard let function = getNowPlayingInfo else {
            completion([:])
            return
        }
        function(DispatchQueue.main, completion)
    }

    /// Fetches the current now playing client (app)
    func fetchNowPlayingClient(completion: @escaping (String?, String?) -> Void) {
        guard let function = getNowPlayingClient,
              let getBundleId = clientGetBundleIdentifier,
              let getDisplayName = clientGetDisplayName else {
            completion(nil, nil)
            return
        }

        function(DispatchQueue.main) { client in
            guard let client = client else {
                completion(nil, nil)
                return
            }

            let bundleId = getBundleId(client) as String?
            let displayName = getDisplayName(client) as String?
            completion(bundleId, displayName)
        }
    }

    /// Checks if any app is currently playing media
    func fetchIsPlaying(completion: @escaping (Bool) -> Void) {
        guard let function = getNowPlayingApplicationIsPlaying else {
            completion(false)
            return
        }
        function(DispatchQueue.main, completion)
    }

    /// Registers for now playing notifications on the given queue
    func registerForNotifications(queue: DispatchQueue = .main) {
        registerForNowPlayingNotifications?(queue)
    }

    /// Unregisters from now playing notifications
    func unregisterForNotifications() {
        unregisterForNowPlayingNotifications?()
    }

    /// Sends a media command
    @discardableResult
    func send(command: MRCommand, options: [String: Any]? = nil) -> Bool {
        guard let function = sendCommand else { return false }
        let cfOptions = options as CFDictionary?
        return function(command.rawValue, cfOptions)
    }

    // MARK: - Convenience Commands

    func togglePlayPause() -> Bool {
        send(command: .togglePlayPause)
    }

    func play() -> Bool {
        send(command: .play)
    }

    func pause() -> Bool {
        send(command: .pause)
    }

    func nextTrack() -> Bool {
        send(command: .nextTrack)
    }

    func previousTrack() -> Bool {
        send(command: .previousTrack)
    }

    func stop() -> Bool {
        send(command: .stop)
    }
}
