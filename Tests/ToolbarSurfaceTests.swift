import XCTest
@testable import SnapBar

final class ToolbarSurfaceTests: XCTestCase {
    func testFloatingToolbarSurfaceProvidesVisibleFallback() {
        let style = ToolbarSurfaceStyle.floatingToolbar

        XCTAssertGreaterThan(style.fallbackFillOpacity, 0.35)
    }
}
