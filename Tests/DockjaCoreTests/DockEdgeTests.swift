import XCTest
@testable import DockjaCore

final class DockEdgeTests: XCTestCase {
    func testIsHorizontal() {
        XCTAssertTrue(DockEdge.top.isHorizontal)
        XCTAssertTrue(DockEdge.bottom.isHorizontal)
        XCTAssertFalse(DockEdge.left.isHorizontal)
        XCTAssertFalse(DockEdge.right.isHorizontal)
    }

    func testCodableRoundTrip() throws {
        for edge in [DockEdge.top, .bottom, .left, .right] {
            let data = try JSONEncoder().encode(edge)
            XCTAssertEqual(try JSONDecoder().decode(DockEdge.self, from: data), edge)
        }
    }
}
