import XCTest
@testable import DockjaCore

final class GroupResolverTests: XCTestCase {
    let enabled: Set<String> = ["brave", "warp", "notes"]
    let groups = [AppGroup(id: "g1", name: "Dev", bundleIDs: ["brave", "warp"])]

    func testNilWhenFrontmostNotEnabled() {
        XCTAssertNil(GroupResolver.unit(frontmost: "mail", enabled: enabled, groups: groups))
    }

    func testNilWhenNoFrontmost() {
        XCTAssertNil(GroupResolver.unit(frontmost: nil, enabled: enabled, groups: groups))
    }

    func testSoloAppShowsItself() {
        XCTAssertEqual(GroupResolver.unit(frontmost: "notes", enabled: enabled, groups: groups), ["notes"])
    }

    func testGroupMemberShowsWholeGroupInOrder() {
        XCTAssertEqual(GroupResolver.unit(frontmost: "warp", enabled: enabled, groups: groups), ["brave", "warp"])
        XCTAssertEqual(GroupResolver.unit(frontmost: "brave", enabled: enabled, groups: groups), ["brave", "warp"])
    }

    func testDisabledMembersAreFilteredOut() {
        let partial: Set<String> = ["warp"]   // brave disabled
        XCTAssertEqual(GroupResolver.unit(frontmost: "warp", enabled: partial, groups: groups), ["warp"])
    }
}
