import AppKit
import XCTest
@testable import SnapBar

final class SelectionBehaviorTests: XCTestCase {
    func testClearingSelectionAllowsSameTextToEmitAgain() {
        var state = SelectionEmissionState()

        XCTAssertEqual(state.textToEmit(from: "repeat"), "repeat")
        XCTAssertNil(state.textToEmit(from: "repeat"))
        XCTAssertNil(state.textToEmit(from: nil))
        XCTAssertEqual(state.textToEmit(from: "repeat"), "repeat")
    }

    func testClipboardFallbackIsLimitedToKnownBrowsers() {
        XCTAssertTrue(ClipboardFallbackPolicy.allowsFallback(for: "com.apple.Safari"))
        XCTAssertTrue(ClipboardFallbackPolicy.allowsFallback(for: "com.google.Chrome"))

        XCTAssertFalse(ClipboardFallbackPolicy.allowsFallback(for: nil))
        XCTAssertFalse(ClipboardFallbackPolicy.allowsFallback(for: "com.apple.finder"))
    }

    func testPasteboardSnapshotRestoresAllItemsAndTypes() {
        let pasteboard = NSPasteboard(name: .init("SnapBarTests.\(UUID().uuidString)"))
        pasteboard.clearContents()

        let first = NSPasteboardItem()
        first.setString("plain", forType: .string)
        first.setData(Data([0xCA, 0xFE]), forType: .init("com.snapbar.test.binary"))

        let second = NSPasteboardItem()
        second.setString("second", forType: .init("com.snapbar.test.second"))

        pasteboard.writeObjects([first, second])
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("selection", forType: .string)

        snapshot.restore(to: pasteboard)

        let restoredItems = pasteboard.pasteboardItems ?? []
        XCTAssertEqual(restoredItems.count, 2)
        XCTAssertEqual(restoredItems[0].string(forType: .string), "plain")
        XCTAssertEqual(restoredItems[0].data(forType: .init("com.snapbar.test.binary")), Data([0xCA, 0xFE]))
        XCTAssertEqual(restoredItems[1].string(forType: .init("com.snapbar.test.second")), "second")
    }

    func testPasteboardSnapshotRestoresEmptyClipboard() {
        let pasteboard = NSPasteboard(name: .init("SnapBarTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)

        pasteboard.setString("selection", forType: .string)
        snapshot.restore(to: pasteboard)

        XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty ?? true)
        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
