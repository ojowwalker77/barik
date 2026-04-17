import XCTest
@testable import Barik

final class LayoutAndWMTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WidgetGridEngine.shared.updateContainerGeometry(
            frame: CGRect(x: 100, y: 50, width: 900, height: 40),
            padding: 10,
            height: 40
        )
    }

    func testGlobalPointConversionUsesContainerFrame() {
        let global = WidgetGridEngine.shared.globalPoint(from: CGPoint(x: 20, y: 5))

        XCTAssertEqual(global.x, 120, accuracy: 0.001)
        XCTAssertEqual(global.y, 55, accuracy: 0.001)
    }

    func testZoneForGlobalLocationUsesGlobalCoordinates() {
        XCTAssertEqual(WidgetGridEngine.shared.zoneForGlobalLocation(CGPoint(x: 150, y: 60)), .left)
        XCTAssertEqual(WidgetGridEngine.shared.zoneForGlobalLocation(CGPoint(x: 520, y: 60)), .center)
        XCTAssertEqual(WidgetGridEngine.shared.zoneForGlobalLocation(CGPoint(x: 930, y: 60)), .right)
    }

    func testAeroSpaceGapRewriteUpdatesTopAndBottomAndResetsSides() {
        let original = """
        [gaps]
        outer.top = 10
        outer.bottom = 15
        outer.left = [{ monitor."^Built-in.*" = 10 }, 30]
        outer.right = 40
        """

        let updated = TilingWMConfigurator.applyingAeroSpaceGapEdits(to: original, barSize: 55, position: .top)

        XCTAssertTrue(updated.contains("outer.top = [{ monitor.\"^Built-in.*\" = 10 }, 55]"))
        XCTAssertTrue(updated.contains("outer.bottom = 10"))
        XCTAssertTrue(updated.contains("outer.left = 10"))
        XCTAssertTrue(updated.contains("outer.right = 10"))
    }

    func testSpacesFilterKeepsEmptyDisplaysEmpty() {
        let leftOnly = AnySpace(AeroSpace(workspace: "1", monitor: "Built-in", isFocused: false, windows: []))

        let filtered = SpacesStore.filterSpaces([leftOnly], monitorName: "External Display")

        XCTAssertTrue(filtered.isEmpty)
    }

    func testConfigurationFailureAllowsRetryForSameTuple() {
        TilingWMConfigurator.resetConfigurationState()
        let request = (barSize: 48, position: BarPosition.top)

        XCTAssertTrue(TilingWMConfigurator.beginConfigurationIfNeeded(request))
        TilingWMConfigurator.finishConfiguration(request, succeeded: false)
        XCTAssertTrue(TilingWMConfigurator.beginConfigurationIfNeeded(request))
    }
}
