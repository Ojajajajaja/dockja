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
}
