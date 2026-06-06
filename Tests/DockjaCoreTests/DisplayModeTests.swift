import XCTest
import Foundation
@testable import DockjaCore

final class DisplayModeTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(DisplayMode.appleDock)
        XCTAssertEqual(try JSONDecoder().decode(DisplayMode.self, from: data), .appleDock)
    }

    func testRawValuesStable() {
        XCTAssertEqual(DisplayMode.compact.rawValue, "compact")
        XCTAssertEqual(DisplayMode.appleDock.rawValue, "appleDock")
    }
}
