import XCTest
@testable import Barik

final class ConfigManagerTests: XCTestCase {
    func testDecodeConfigReadsSystemSettings() throws {
        let contents = """
        theme = "dark"

        [widgets]
        displayed = ["default.time"]

        [zonedLayout]
        left = ["default.spaces"]
        center = ["default.time"]
        right = ["default.battery"]

        [system]
        manage-menu-bar-autohide = true
        """

        let config = try ConfigManager.decodeConfig(contents: contents)

        XCTAssertEqual(config.theme, .dark)
        XCTAssertTrue(config.system.manageMenuBarAutohide)
    }

    func testEncodeConfigOmitsDefaultSystemSection() {
        let contents = ConfigTOMLEncoder.encode(.init())

        XCTAssertFalse(contents.contains("[system]"))
    }

    func testDecodeInvalidConfigThrows() {
        let contents = """
        theme = "dark
        """

        XCTAssertThrowsError(try ConfigManager.decodeConfig(contents: contents))
    }

    func testShouldReloadConfigWhenContentsMatchButErrorIsActive() {
        XCTAssertTrue(
            ConfigManager.shouldReloadConfig(
                contents: "theme = \"dark\"",
                lastLoadedContents: "theme = \"dark\"",
                hasActiveLoadError: true
            )
        )
    }
}
