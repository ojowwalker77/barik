import XCTest
@testable import Barik

final class NetworkWidgetTests: XCTestCase {
    func testConnectedWifiKeepsWifiSymbolWhenSSIDIsUnavailable() {
        XCTAssertEqual(
            NetworkWidget.wifiSymbolName(for: .connected, ssid: "Not connected"),
            "wifi"
        )
    }
}
