import XCTest
import CoreGraphics
@testable import DockjaCore

final class WindowOrderStabilizerTests: XCTestCase {
    private func win(_ id: CGWindowID, _ title: String, pid: pid_t = 1) -> WindowInfo {
        WindowInfo(ref: WindowRef(), id: id, title: title,
                   isMinimized: false, isActive: false, pid: pid)
    }

    func testFirstCallKeepsLiveOrder() {
        var sut = WindowOrderStabilizer()
        let out = sut.stableOrder(pid: 1, windows: [win(1, "A"), win(2, "B"), win(3, "C")])
        XCTAssertEqual(out.map(\.id), [1, 2, 3])
    }

    func testReorderedLiveListKeepsRememberedSlots() {
        var sut = WindowOrderStabilizer()
        _ = sut.stableOrder(pid: 1, windows: [win(1, "A"), win(2, "B"), win(3, "C")])
        // AX now returns them in a different (focus-driven) order.
        let out = sut.stableOrder(pid: 1, windows: [win(2, "B"), win(3, "C"), win(1, "A")])
        XCTAssertEqual(out.map(\.id), [1, 2, 3])
    }

    func testNewWindowAppendsAtEnd() {
        var sut = WindowOrderStabilizer()
        _ = sut.stableOrder(pid: 1, windows: [win(1, "A"), win(2, "B")])
        let out = sut.stableOrder(pid: 1, windows: [win(9, "D"), win(1, "A"), win(2, "B")])
        XCTAssertEqual(out.map(\.id), [1, 2, 9])
    }

    func testClosedWindowDropsOut() {
        var sut = WindowOrderStabilizer()
        _ = sut.stableOrder(pid: 1, windows: [win(1, "A"), win(2, "B"), win(3, "C")])
        let out = sut.stableOrder(pid: 1, windows: [win(3, "C"), win(1, "A")])
        XCTAssertEqual(out.map(\.id), [1, 3])
    }

    func testReopenedWindowAppendsRatherThanReclaimingOldSlot() {
        var sut = WindowOrderStabilizer()
        _ = sut.stableOrder(pid: 1, windows: [win(1, "A"), win(2, "B"), win(3, "C")])
        _ = sut.stableOrder(pid: 1, windows: [win(1, "A"), win(3, "C")])          // 2 closed
        let out = sut.stableOrder(pid: 1, windows: [win(1, "A"), win(2, "B"), win(3, "C")]) // 2 back
        XCTAssertEqual(out.map(\.id), [1, 3, 2])
    }

    func testOrderIsIndependentPerPID() {
        var sut = WindowOrderStabilizer()
        _ = sut.stableOrder(pid: 1, windows: [win(1, "A", pid: 1), win(2, "B", pid: 1)])
        let out = sut.stableOrder(pid: 2, windows: [win(5, "X", pid: 2), win(4, "Y", pid: 2)])
        XCTAssertEqual(out.map(\.id), [5, 4])
    }

    func testHandlesDuplicateUnavailableIDsWithoutDroppingWindows() {
        // When the window id is unavailable (0) for several windows, none are lost.
        var sut = WindowOrderStabilizer()
        let out = sut.stableOrder(pid: 1, windows: [win(0, "A"), win(0, "B"), win(0, "C")])
        XCTAssertEqual(out.count, 3)
    }
}
