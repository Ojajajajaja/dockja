import XCTest
import CoreGraphics
@testable import DockjaCore

final class SettingsStoreTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dockja-test-\(UUID().uuidString)")
    }

    func testDefaultsAreEmpty() {
        let store = SettingsStore(directory: tempDir())
        XCTAssertEqual(store.settings.enabledBundleIDs, [])
        XCTAssertNil(store.settings.barFrame)
        XCTAssertTrue(store.enabledSet.isEmpty)
    }

    func testRoundTripPersistsAcrossInstances() {
        let dir = tempDir()
        let store1 = SettingsStore(directory: dir)
        store1.update {
            $0.enabledBundleIDs = ["com.apple.Safari"]
            $0.barFrame = CGRect(x: 1, y: 2, width: 3, height: 4)
        }

        let store2 = SettingsStore(directory: dir)
        XCTAssertEqual(store2.settings.enabledBundleIDs, ["com.apple.Safari"])
        XCTAssertEqual(store2.settings.barFrame, CGRect(x: 1, y: 2, width: 3, height: 4))
        XCTAssertEqual(store2.enabledSet, ["com.apple.Safari"])
    }

    func testNewFieldsDefaultWhenDecodingOldJSON() throws {
        // Old settings.json written before these fields existed.
        let json = #"{"enabledBundleIDs":["com.apple.Safari"]}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(s.enabledBundleIDs, ["com.apple.Safari"])
        XCTAssertEqual(s.displayMode, .compact)
        XCTAssertEqual(s.dockEdge, .bottom)
        XCTAssertNil(s.dockParallel)
        XCTAssertEqual(s.recentIcons, [])
        XCTAssertEqual(s.dockIconSize, 48)   // default when absent
        XCTAssertFalse(s.autoHide)           // default when absent
    }

    func testNewFieldsRoundTrip() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockja-test-\(UUID().uuidString)")
        let store = SettingsStore(directory: dir)
        store.update {
            $0.displayMode = .appleDock
            $0.dockEdge = .left
            $0.dockParallel = 120
            $0.recentIcons = ["/a.png", "/b.png"]
            $0.dockIconSize = 64
            $0.autoHide = true
            $0.groups = [AppGroup(id: "g1", name: "Dev", bundleIDs: ["brave", "warp"])]
        }
        let reloaded = SettingsStore(directory: dir)
        XCTAssertEqual(reloaded.settings.displayMode, .appleDock)
        XCTAssertEqual(reloaded.settings.dockEdge, .left)
        XCTAssertEqual(reloaded.settings.dockParallel, 120)
        XCTAssertEqual(reloaded.settings.recentIcons, ["/a.png", "/b.png"])
        XCTAssertEqual(reloaded.settings.dockIconSize, 64)
        XCTAssertTrue(reloaded.settings.autoHide)
        XCTAssertEqual(reloaded.settings.groups, [AppGroup(id: "g1", name: "Dev", bundleIDs: ["brave", "warp"])])
    }
}
