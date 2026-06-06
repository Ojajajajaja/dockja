import XCTest
import CoreGraphics
@testable import DockjaCore

final class EdgeSnapperTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let snapper = EdgeSnapper()

    func testNearestEdge() {
        XCTAssertEqual(snapper.nearestEdge(barCenter: CGPoint(x: 20, y: 400), screen: screen), .left)
        XCTAssertEqual(snapper.nearestEdge(barCenter: CGPoint(x: 980, y: 400), screen: screen), .right)
        XCTAssertEqual(snapper.nearestEdge(barCenter: CGPoint(x: 500, y: 20), screen: screen), .bottom)
        XCTAssertEqual(snapper.nearestEdge(barCenter: CGPoint(x: 500, y: 780), screen: screen), .top)
    }

    func testOriginBottomIsFlushAndClamped() {
        let o = snapper.origin(for: .bottom, size: CGSize(width: 200, height: 50),
                               parallel: 5000, screen: screen)
        XCTAssertEqual(o.y, 0)            // flush to bottom
        XCTAssertEqual(o.x, 800)          // clamped to maxX - width
    }

    func testOriginTopIsFlush() {
        let o = snapper.origin(for: .top, size: CGSize(width: 200, height: 50),
                               parallel: 100, screen: screen)
        XCTAssertEqual(o.y, 750)          // maxY - height
        XCTAssertEqual(o.x, 100)
    }

    func testOriginLeftIsFlushAndClamped() {
        let o = snapper.origin(for: .left, size: CGSize(width: 50, height: 200),
                               parallel: -100, screen: screen)
        XCTAssertEqual(o.x, 0)            // flush to left
        XCTAssertEqual(o.y, 0)            // clamped to minY
    }

    func testOriginRightIsFlush() {
        let o = snapper.origin(for: .right, size: CGSize(width: 50, height: 200),
                               parallel: 300, screen: screen)
        XCTAssertEqual(o.x, 950)          // maxX - width
        XCTAssertEqual(o.y, 300)
    }
}
