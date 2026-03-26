import os
import Foundation

let logger = Logger(subsystem: "com.snapbar.app", category: "SnapBar")

/// Debug logger that writes to both os_log and ~/.snapbar/debug.log
enum DebugLog {
    private nonisolated(unsafe) static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    static let fileURL: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".snapbar/debug.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }()

    private static let maxLogSize: UInt64 = 2 * 1024 * 1024  // 2 MB

    static func log(_ message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        logger.notice("\(message)")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    // Rotate if too large
                    let size = handle.seekToEndOfFile()
                    if size > maxLogSize {
                        handle.closeFile()
                        rotateLog()
                        try? data.write(to: fileURL)
                    } else {
                        handle.write(data)
                        handle.closeFile()
                    }
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    private static func rotateLog() {
        let oldURL = fileURL.deletingLastPathComponent().appendingPathComponent("debug.old.log")
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: fileURL, to: oldURL)
    }
}
