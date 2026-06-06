import XCTest
@testable import DockjaCore

final class RecentIconsTests: XCTestCase {
    func testAddMovesToFront() {
        var r = RecentIcons(paths: ["/a", "/b"])
        r.add("/b")
        XCTAssertEqual(r.paths, ["/b", "/a"])
    }

    func testAddDedups() {
        var r = RecentIcons(paths: ["/a"])
        r.add("/a")
        XCTAssertEqual(r.paths, ["/a"])
    }

    func testAddCaps() {
        var r = RecentIcons()
        for i in 0..<20 { r.add("/\(i)", cap: 12) }
        XCTAssertEqual(r.paths.count, 12)
        XCTAssertEqual(r.paths.first, "/19")
        XCTAssertEqual(r.paths.last, "/8")
    }

    func testCodableRoundTrip() throws {
        let r = RecentIcons(paths: ["/a", "/b"])
        let data = try JSONEncoder().encode(r)
        XCTAssertEqual(try JSONDecoder().decode(RecentIcons.self, from: data), r)
    }
}
