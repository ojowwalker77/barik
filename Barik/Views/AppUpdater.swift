import Combine
import Foundation

final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    @Published var latestVersion: String?
    @Published var updateAvailable = false

    private(set) var downloadedUpdatePath: String?
    private var updateAssetURL: URL?
    private var updateTimer: Timer?

    init(startImmediately: Bool = true) {
        guard startImmediately else { return }
        fetchLatestRelease()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.fetchLatestRelease()
        }
    }

    deinit {
        updateTimer?.invalidate()
    }

    private func fallbackDownloadURL(for version: String) -> URL? {
        let versionWithoutPrefix = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return URL(string: "https://github.com/ojowwalker77/barik/releases/download/v\(versionWithoutPrefix)/Barik.zip")
    }

    func fetchLatestRelease() {
        guard let url = URL(string: "https://api.github.com/repos/ojowwalker77/barik/releases/latest") else {
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            if let error {
                AppDiagnostics.shared.post(id: "update-check", kind: .update, title: "Update Check Failed", message: error.localizedDescription)
                return
            }
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = json["tag_name"] as? String
            else {
                return
            }

            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String,
                       name.hasSuffix(".zip"),
                       let downloadURLString = asset["browser_download_url"] as? String,
                       let assetURL = URL(string: downloadURLString) {
                        self?.updateAssetURL = assetURL
                        break
                    }
                }
            }

            let currentVersion = VersionChecker.currentVersion ?? "0.0.0"
            let comparisonResult = self?.compareVersion(tag, currentVersion) ?? 0
            DispatchQueue.main.async {
                self?.latestVersion = tag
                self?.updateAvailable = comparisonResult > 0
                AppDiagnostics.shared.clear(id: "update-check")
            }
        }.resume()
    }

    func compareVersion(_ v1: String, _ v2: String) -> Int {
        let version1 = v1.replacingOccurrences(of: "v", with: "")
        let version2 = v2.replacingOccurrences(of: "v", with: "")
        let parts1 = version1.split(separator: ".").compactMap { Int($0) }
        let parts2 = version2.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let num1 = i < parts1.count ? parts1[i] : 0
            let num2 = i < parts2.count ? parts2[i] : 0
            if num1 > num2 { return 1 }
            if num1 < num2 { return -1 }
        }
        return 0
    }

    func downloadAndInstall(latest version: String, completion: @escaping (Bool) -> Void) {
        downloadAndUnzip(latest: version) { [weak self] tempDir in
            guard let self, let tempDir else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            do {
                try self.validateDownloadedApp(at: tempDir.appendingPathComponent("Barik.app"), advertisedVersion: version)
                self.downloadedUpdatePath = tempDir.path
                try self.installUpdate(latest: version)
                DispatchQueue.main.async {
                    completion(true)
                }
            } catch {
                AppDiagnostics.shared.post(id: "update-install", kind: .update, title: "Update Failed", message: error.localizedDescription)
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }

    private func downloadAndUnzip(latest version: String, completion: @escaping (URL?) -> Void) {
        let assetURL: URL
        if let url = updateAssetURL {
            assetURL = url
        } else if let fallbackURL = fallbackDownloadURL(for: version) {
            assetURL = fallbackURL
        } else {
            completion(nil)
            return
        }

        URLSession.shared.downloadTask(with: assetURL) { localURL, response, error in
            if let error {
                AppDiagnostics.shared.post(id: "update-download", kind: .update, title: "Download Failed", message: error.localizedDescription)
                completion(nil)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                AppDiagnostics.shared.post(id: "update-download", kind: .update, title: "Download Failed", message: "Unexpected HTTP response while downloading Barik.")
                completion(nil)
                return
            }
            guard let localURL else {
                completion(nil)
                return
            }

            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzipProcess.arguments = ["-o", localURL.path, "-d", tempDir.path]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                guard unzipProcess.terminationStatus == 0 else {
                    throw UpdaterError.unzipFailed
                }

                completion(tempDir)
            } catch {
                AppDiagnostics.shared.post(id: "update-download", kind: .update, title: "Unzip Failed", message: error.localizedDescription)
                completion(nil)
            }
        }.resume()
    }

    func validateDownloadedApp(at appURL: URL, advertisedVersion: String) throws {
        let bundle = Bundle(url: appURL)

        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw UpdaterError.missingDownloadedApp
        }
        guard let bundle else {
            throw UpdaterError.invalidBundle
        }

        guard bundle.bundleIdentifier == (Bundle.main.bundleIdentifier ?? "jow.Barik") else {
            throw UpdaterError.bundleIdentifierMismatch
        }

        let downloadedVersion = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        guard compareVersion(downloadedVersion, advertisedVersion) >= 0 else {
            throw UpdaterError.versionMismatch
        }
    }

    func installScriptContents(downloadedAppURL: URL, destinationURL: URL) -> String {
        let backupPath = "\(destinationURL.path).bak.$(date +%s)"
        return """
        #!/bin/bash
        set -euo pipefail
        NEW_APP="\(downloadedAppURL.path)"
        DEST_APP="\(destinationURL.path)"
        BACKUP_APP="${backupPath}"

        if [ -d "${DEST_APP}" ]; then
          mv "${DEST_APP}" "${BACKUP_APP}"
        fi

        if ! mv "${NEW_APP}" "${DEST_APP}"; then
          if [ -d "${BACKUP_APP}" ]; then
            mv "${BACKUP_APP}" "${DEST_APP}"
          fi
          exit 1
        fi

        open "${DEST_APP}"
        sleep 5

        if pgrep -f "${DEST_APP}/Contents/MacOS/Barik" >/dev/null 2>&1; then
          if [ -d "${BACKUP_APP}" ]; then
            rm -rf "${BACKUP_APP}"
          fi
        else
          rm -rf "${DEST_APP}"
          if [ -d "${BACKUP_APP}" ]; then
            mv "${BACKUP_APP}" "${DEST_APP}"
            open "${DEST_APP}"
          fi
          exit 1
        fi

        rm -- "$0"
        """
    }

    func installUpdate(latest version: String) throws {
        guard let downloadedPath = downloadedUpdatePath else {
            throw UpdaterError.missingDownloadedApp
        }

        let newAppURL = URL(fileURLWithPath: downloadedPath).appendingPathComponent("Barik.app")
        let destinationURL = URL(fileURLWithPath: "/Applications/Barik.app")
        let script = installScriptContents(downloadedAppURL: newAppURL, destinationURL: destinationURL)

        let fileManager = FileManager.default
        let updateTempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: updateTempDir, withIntermediateDirectories: true, attributes: nil)
        let scriptURL = updateTempDir.appendingPathComponent("update.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = scriptURL
        try process.run()
    }
}

enum UpdaterError: LocalizedError {
    case missingDownloadedApp
    case invalidBundle
    case bundleIdentifierMismatch
    case versionMismatch
    case unzipFailed

    var errorDescription: String? {
        switch self {
        case .missingDownloadedApp:
            return "The downloaded Barik.app could not be found."
        case .invalidBundle:
            return "The downloaded update is not a valid app bundle."
        case .bundleIdentifierMismatch:
            return "The downloaded update does not match Barik's bundle identifier."
        case .versionMismatch:
            return "The downloaded update version does not match the advertised release."
        case .unzipFailed:
            return "Barik.zip could not be extracted."
        }
    }
}
