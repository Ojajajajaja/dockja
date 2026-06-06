import XCTest
import CoreGraphics
@testable import DockjaCore

final class WindowOverrideStoreTests: XCTestCase {
    func testSetNameAndIcon() {
        let store = WindowOverrideStore()
        store.setName("Build", for: 5)
        store.setIcon("/a.png", for: 5)
        XCTAssertEqual(store.override(for: 5).customName, "Build")
        XCTAssertEqual(store.override(for: 5).iconPath, "/a.png")
        XCTAssertEqual(store.overrides()[5]?.customName, "Build")
    }

    func testResetRemoves() {
        let store = WindowOverrideStore()
        store.setName("Build", for: 5)
        store.reset(5)
        XCTAssertTrue(store.overrides().isEmpty)
        XCTAssertNil(store.override(for: 5).customName)
    }

    func testClearingBothFieldsDropsEntry() {
        let store = WindowOverrideStore()
        store.setName("Build", for: 5)
        store.setName(nil, for: 5)   // now empty
        XCTAssertTrue(store.overrides().isEmpty)
    }

    func testPruneKeepsOnlyLiveIDs() {
        let store = WindowOverrideStore()
        store.setName("A", for: 1)
        store.setName("B", for: 2)
        store.prune(keeping: [2])
        XCTAssertNil(store.overrides()[1])
        XCTAssertEqual(store.overrides()[2]?.customName, "B")
    }

    func testClearingIconAloneKeepsEntryWhenNamePresent() {
        let store = WindowOverrideStore()
        store.setName("Build", for: 5)
        store.setIcon("/a.png", for: 5)
        store.setIcon(nil, for: 5)
        XCTAssertEqual(store.override(for: 5).customName, "Build")
        XCTAssertNil(store.override(for: 5).iconPath)
        XCTAssertNotNil(store.overrides()[5])
    }

    func testClearingIconAloneDropsEntryWhenNameAbsent() {
        let store = WindowOverrideStore()
        store.setIcon("/a.png", for: 5)
        store.setIcon(nil, for: 5)
        XCTAssertTrue(store.overrides().isEmpty)
    }

    func testWhitespaceOnlyNameTreatedAsEmpty() {
        let store = WindowOverrideStore()
        store.setName("   ", for: 5)
        XCTAssertTrue(store.overrides().isEmpty)
    }
}
