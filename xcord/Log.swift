//
//  Log.swift
//  xcord
//

import Foundation

enum Log {
    static func info(_ message: String) {
        write("INFO", message)
    }

    static func warn(_ message: String) {
        write("WARN", message)
    }

    static func error(_ message: String) {
        write("ERROR", message)
    }

    private static func write(_ level: String, _ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        FileHandle.standardError.write("\(timestamp) [\(level)] \(message)\n".data(using: .utf8)!)
    }
}
