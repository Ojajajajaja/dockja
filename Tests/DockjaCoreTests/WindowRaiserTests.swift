import XCTest
@testable import DockjaCore

final class WindowRaiserTests: XCTestCase {
    func testRaiseUnminimizesThenActivatesRaisesSetsMain() {
        let fake = FakeAccessibilityProvider()
        fake.addWindow(pid: 7, id: 9, title: "W", minimized: true)
        let info = WindowEnumerator(provider: fake).windows(forPID: 7)[0]

        WindowRaiser(provider: fake).raise(info)

        XCTAssertEqual(fake.calls, ["unminimize(9)", "activate(7)", "raise(9)", "setMain(9)"])
    }

    func testRaiseSkipsUnminimizeWhenNotMinimized() {
        let fake = FakeAccessibilityProvider()
        fake.addWindow(pid: 7, id: 9, title: "W")
        let info = WindowEnumerator(provider: fake).windows(forPID: 7)[0]

        WindowRaiser(provider: fake).raise(info)

        XCTAssertEqual(fake.calls, ["activate(7)", "raise(9)", "setMain(9)"])
    }
}
