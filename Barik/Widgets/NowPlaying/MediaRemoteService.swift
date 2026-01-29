import AppKit
import Combine
import Foundation

// MARK: - MediaRemote Service

/// Service that provides universal media detection via mediaremote-adapter
/// Works on all macOS versions including 15.4+ by using Perl workaround
final class MediaRemoteService: ObservableObject {
    static let shared = MediaRemoteService()

    // MARK: - Published State

    @Published private(set) var nowPlaying: NowPlayingInfo?
    @Published private(set) var isAvailable: Bool = false

    // MARK: - Private Properties

    private let adapter = MediaRemoteAdapter()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        // Check if adapter resources exist in bundle
        let hasScript = Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl") != nil
        let resourcePath = Bundle.main.resourcePath ?? ""
        let frameworkPath = (resourcePath as NSString).appendingPathComponent("MediaRemoteAdapter.framework")
        let hasFramework = FileManager.default.fileExists(atPath: frameworkPath)

        isAvailable = hasScript && hasFramework

        if isAvailable {
            setupAdapterBinding()
            adapter.start()
        } else {
            print("[MediaRemoteService] Adapter resources not found in bundle - falling back to AppleScript")
        }
    }

    deinit {
        adapter.stop()
    }

    // MARK: - Setup

    private func setupAdapterBinding() {
        adapter.$nowPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: &$nowPlaying)
    }

    // MARK: - Playback Commands

    @discardableResult
    func togglePlayPause() -> Bool {
        guard isAvailable else { return false }
        adapter.togglePlayPause()
        return true
    }

    @discardableResult
    func play() -> Bool {
        guard isAvailable else { return false }
        adapter.play()
        return true
    }

    @discardableResult
    func pause() -> Bool {
        guard isAvailable else { return false }
        adapter.pause()
        return true
    }

    @discardableResult
    func nextTrack() -> Bool {
        guard isAvailable else { return false }
        adapter.nextTrack()
        return true
    }

    @discardableResult
    func previousTrack() -> Bool {
        guard isAvailable else { return false }
        adapter.previousTrack()
        return true
    }

    @discardableResult
    func stop() -> Bool {
        guard isAvailable else { return false }
        adapter.sendCommand("stop")
        return true
    }

    // MARK: - One-shot Fetch

    func fetchNowPlaying() {
        adapter.fetchOnce { [weak self] info in
            self?.nowPlaying = info
        }
    }
}
