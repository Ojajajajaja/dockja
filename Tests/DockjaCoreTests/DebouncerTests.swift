import XCTest
@testable import DockjaCore

final class DebouncerTests: XCTestCase {
    func testCoalescesRapidCallsIntoOne() {
        let d = Debouncer(interval: 0.05)
        var count = 0
        for _ in 0..<5 { d.call { count += 1 } }

        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)

        XCTAssertEqual(count, 1)
    }
}
