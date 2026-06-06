import XCTest
@testable import DockjaCore

final class WindowEnumeratorTests: XCTestCase {
    func testMapsWindowsWithTitlesAndFlags() {
        let fake = FakeAccessibilityProvider()
        fake.addWindow(pid: 42, id: 1, title: "Gmail", main: true)
        fake.addWindow(pid: 42, id: 2, title: "", minimized: true)

        let result = WindowEnumerator(provider: fake).windows(forPID: 42)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].title, "Gmail")
        XCTAssertTrue(result[0].isActive)
        XCTAssertEqual(result[0].displayLabel, "Gmail")
        XCTAssertEqual(result[0].pid, 42)
        XCTAssertTrue(result[1].isMinimized)
        XCTAssertEqual(result[1].displayLabel, "Untitled")
    }

    func testReturnsEmptyForUnknownPID() {
        let fake = FakeAccessibilityProvider()
        XCTAssertTrue(WindowEnumerator(provider: fake).windows(forPID: 99).isEmpty)
    }
}
