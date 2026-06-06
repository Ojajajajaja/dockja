import XCTest
@testable import DockjaCore

final class BarVisibilityTests: XCTestCase {
    let enabled: Set<String> = ["com.apple.Safari"]

    func testVisibleWhenEnabledAndHasWindows() {
        XCTAssertEqual(
            barState(frontmostBundleID: "com.apple.Safari", enabled: enabled, windowCount: 3),
            .visible(bundleID: "com.apple.Safari")
        )
    }

    func testHiddenWhenNotEnabled() {
        XCTAssertEqual(
            barState(frontmostBundleID: "com.apple.Mail", enabled: enabled, windowCount: 3),
            .hidden
        )
    }

    func testHiddenWhenEnabledButNoWindows() {
        XCTAssertEqual(
            barState(frontmostBundleID: "com.apple.Safari", enabled: enabled, windowCount: 0),
            .hidden
        )
    }

    func testHiddenWhenNoFrontmostApp() {
        XCTAssertEqual(
            barState(frontmostBundleID: nil, enabled: enabled, windowCount: 3),
            .hidden
        )
    }
}
