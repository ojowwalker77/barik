import XCTest
@testable import Barik

final class AppUpdaterTests: XCTestCase {
    func testCompareVersionOrdersSemanticVersions() {
        let updater = AppUpdater(startImmediately: false)

        XCTAssertEqual(updater.compareVersion("v1.2.0", "1.1.9"), 1)
        XCTAssertEqual(updater.compareVersion("1.2.0", "1.2.0"), 0)
        XCTAssertEqual(updater.compareVersion("1.1.9", "1.2.0"), -1)
    }

    func testInstallScriptUsesBackupAndRestoreFlow() {
        let updater = AppUpdater(startImmediately: false)
        let script = updater.installScriptContents(
            downloadedAppURL: URL(fileURLWithPath: "/tmp/Barik.app"),
            destinationURL: URL(fileURLWithPath: "/Applications/Barik.app")
        )

        XCTAssertTrue(script.contains("BACKUP_APP"))
        XCTAssertTrue(script.contains("mv \"${DEST_APP}\" \"${BACKUP_APP}\""))
        XCTAssertTrue(script.contains("if pgrep -f \"${DEST_APP}/Contents/MacOS/Barik\""))
        XCTAssertTrue(script.contains("mv \"${BACKUP_APP}\" \"${DEST_APP}\""))
    }

    func testValidateDownloadedAppAcceptsMatchingBundle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appURL = tempDir.appendingPathComponent("Barik.app")
        let contentsURL = appURL.appendingPathComponent("Contents")
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")

        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true, attributes: nil)
        let plist: [String: Any] = [
            "CFBundleIdentifier": Bundle.main.bundleIdentifier ?? "jow.Barik",
            "CFBundleShortVersionString": "9.9.9",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: infoPlistURL)

        XCTAssertNoThrow(try AppUpdater(startImmediately: false).validateDownloadedApp(at: appURL, advertisedVersion: "1.0.0"))
    }
}
