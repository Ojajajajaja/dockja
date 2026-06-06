import XCTest
import CoreGraphics
@testable import DockjaCore

final class OverrideResolverTests: XCTestCase {
    private func win(_ id: CGWindowID, _ title: String) -> WindowInfo {
        WindowInfo(ref: WindowRef(), id: id, title: title,
                   isMinimized: false, isActive: false, pid: 1)
    }

    func testUsesTitleWhenNoOverride() {
        let out = OverrideResolver().resolve([win(1, "Gmail")], overrides: [:])
        XCTAssertEqual(out[0].name, "Gmail")
        XCTAssertNil(out[0].iconPath)
        XCTAssertEqual(out[0].window.id, 1)
    }

    func testCustomNameWins() {
        let ov: [CGWindowID: WindowOverride] = [1: WindowOverride(customName: "Build", iconPath: "/a.png")]
        let out = OverrideResolver().resolve([win(1, "Gmail")], overrides: ov)
        XCTAssertEqual(out[0].name, "Build")
        XCTAssertEqual(out[0].iconPath, "/a.png")
    }

    func testEmptyCustomNameFallsBackToTitle() {
        let ov: [CGWindowID: WindowOverride] = [1: WindowOverride(customName: "", iconPath: nil)]
        let out = OverrideResolver().resolve([win(1, "Gmail")], overrides: ov)
        XCTAssertEqual(out[0].name, "Gmail")
    }

    func testUntitledFallback() {
        let out = OverrideResolver().resolve([win(2, "")], overrides: [:])
        XCTAssertEqual(out[0].name, "Untitled")
    }

    func testEmptyIconPathNilsOut() {
        let ov: [CGWindowID: WindowOverride] = [1: WindowOverride(customName: nil, iconPath: "")]
        let out = OverrideResolver().resolve([win(1, "Gmail")], overrides: ov)
        XCTAssertNil(out[0].iconPath)
        XCTAssertEqual(out[0].name, "Gmail")
    }
}
