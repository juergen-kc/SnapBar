import XCTest
@testable import SnapBar

final class ToolbarSurfaceTests: XCTestCase {
    func testFloatingToolbarSurfaceProvidesVisibleFallback() {
        let style = ToolbarSurfaceStyle.floatingToolbar

        XCTAssertTrue(style.hasVisibleFallback)
        XCTAssertGreaterThan(style.fallbackFillOpacity, 0.35)
        XCTAssertGreaterThan(style.strokeOpacity, 0)
        XCTAssertGreaterThan(style.shadowOpacity, 0)
        XCTAssertGreaterThan(style.shadowRadius, 0)
    }
}
