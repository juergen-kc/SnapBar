import os
import Foundation

/// Debug logger that writes to both os_log and ~/.snapbar/debug.log
enum DebugLog {
    private static let logger = Logger(subsystem: "com.snapbar.app", category: "SnapBar")
    private nonisolated(unsafe) static let formatter = ISO8601DateFormatter()

    static let fileURL: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".snapbar/debug.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }()

    private static let maxLogSize: UInt64 = 2 * 1024 * 1024  // 2 MB

    static func log(_ message: String) {
        logger.notice("\(message)")
        guard let data = "[\(formatter.string(from: Date()))] \(message)\n".data(using: .utf8) else { return }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            try? data.write(to: fileURL)
            return
        }
        defer { handle.closeFile() }
        guard handle.seekToEndOfFile() <= maxLogSize else {
            rotateLog()
            try? data.write(to: fileURL)
            return
        }
        handle.write(data)
    }

    private static func rotateLog() {
        let oldURL = fileURL.deletingLastPathComponent().appendingPathComponent("debug.old.log")
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: fileURL, to: oldURL)
    }
}
