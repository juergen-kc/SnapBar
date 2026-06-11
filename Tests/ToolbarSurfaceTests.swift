import XCTest
@testable import SnapBar

final class ToolbarSurfaceTests: XCTestCase {
    func testFloatingToolbarSurfaceProvidesVisibleFallback() {
        let style = ToolbarSurfaceStyle.floatingToolbar

        XCTAssertTrue(style.hasVisibleFallback)
        XCTAssertGreaterThan(style.fallbackFillOpacity, 0.35)
    }
}
