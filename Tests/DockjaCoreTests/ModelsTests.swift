import XCTest
@testable import DockjaCore

final class ModelsTests: XCTestCase {
    func testDisplayLabelUsesTitleWhenPresent() {
        let info = WindowInfo(ref: WindowRef(), title: "Gmail",
                              isMinimized: false, isActive: true, pid: 1)
        XCTAssertEqual(info.displayLabel, "Gmail")
    }

    func testDisplayLabelFallsBackWhenTitleEmpty() {
        let info = WindowInfo(ref: WindowRef(), title: "",
                              isMinimized: false, isActive: false, pid: 1)
        XCTAssertEqual(info.displayLabel, "Untitled")
    }
}
