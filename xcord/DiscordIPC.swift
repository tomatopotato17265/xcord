//
//  DiscordIPC.swift
//  xcord
//

import Darwin
import Foundation

enum DiscordIPCError: Error {
    case socketNotFound
    case socketCreationFailed(errno: Int32)
    case connectFailed(errno: Int32)
    case writeFailed(errno: Int32)
    case readFailed(errno: Int32)
    case connectionClosed
    case notConnected
    case pathTooLong
}

enum DiscordOpcode: Int32 {
    case handshake = 0
    case frame = 1
    case close = 2
}

final class DiscordIPCTransport {
    private var socketFD: Int32 = -1
    var isConnected: Bool { socketFD >= 0 }

    func connect() throws {
        guard socketFD < 0 else { return }
        socketFD = try openSocket()
    }

    func close() {
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }

    func writeFrame(opcode: DiscordOpcode, payload: Data) throws {
        guard socketFD >= 0 else { throw DiscordIPCError.notConnected }

        var header = Data()
        header.append(littleEndianBytes(opcode.rawValue))
        header.append(littleEndianBytes(Int32(payload.count)))

        try writeAll(header + payload)
    }

    func readFrame() throws -> (opcode: Int32, payload: Data) {
        let header = try readExactly(8)
        let opcode = header.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int32.self) }.littleEndian
        let length = header.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Int32.self) }.littleEndian
        let payload = length > 0 ? try readExactly(Int(length)) : Data()
        return (opcode, payload)
    }

    // MARK: - Socket discovery & connection

    private func openSocket() throws -> Int32 {
        let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()

        for index in 0...9 {
            let path = tmpDir.hasSuffix("/") ? "\(tmpDir)discord-ipc-\(index)" : "\(tmpDir)/discord-ipc-\(index)"
            guard FileManager.default.fileExists(atPath: path) else { continue }
            if let fd = try? connectSocket(atPath: path) {
                return fd
            }
        }

        throw DiscordIPCError.socketNotFound
    }

    private func connectSocket(atPath path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DiscordIPCError.socketCreationFailed(errno: errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(path.utf8)
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < maxPathLength else {
            Darwin.close(fd)
            throw DiscordIPCError.pathTooLong
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { rawPtr in
            rawPtr.withMemoryRebound(to: CChar.self, capacity: maxPathLength) { charPtr in
                for (i, byte) in pathBytes.enumerated() {
                    charPtr[i] = CChar(bitPattern: byte)
                }
                charPtr[pathBytes.count] = 0
            }
        }

        let addrLen = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count + 1)
        let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }

        guard result == 0 else {
            let err = errno
            Darwin.close(fd)
            throw DiscordIPCError.connectFailed(errno: err)
        }

        return fd
    }

    // MARK: - Raw read/write

    private func writeAll(_ data: Data) throws {
        guard socketFD >= 0 else { throw DiscordIPCError.notConnected }

        try data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            var offset = 0
            let total = rawBuffer.count
            while offset < total {
                let written = Darwin.write(socketFD, rawBuffer.baseAddress!.advanced(by: offset), total - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw DiscordIPCError.writeFailed(errno: errno)
                }
                if written == 0 { throw DiscordIPCError.connectionClosed }
                offset += written
            }
        }
    }

    private func readExactly(_ count: Int) throws -> Data {
        guard socketFD >= 0 else { throw DiscordIPCError.notConnected }

        var data = Data(capacity: count)
        var buffer = [UInt8](repeating: 0, count: min(count, 4096))

        while data.count < count {
            let toRead = min(buffer.count, count - data.count)
            let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(socketFD, rawBuffer.baseAddress, toRead)
            }
            if bytesRead < 0 {
                if errno == EINTR { continue }
                throw DiscordIPCError.readFailed(errno: errno)
            }
            if bytesRead == 0 { throw DiscordIPCError.connectionClosed }
            data.append(contentsOf: buffer[0..<bytesRead])
        }

        return data
    }

    private func littleEndianBytes(_ value: Int32) -> Data {
        var le = value.littleEndian
        return Data(bytes: &le, count: MemoryLayout<Int32>.size)
    }
}

final class DiscordIPC {
    private let clientID: String
    private let transport = DiscordIPCTransport()

    var isConnected: Bool { transport.isConnected }

    init(clientID: String) {
        self.clientID = clientID
    }

    func connect() throws {
        try transport.connect()

        do {
            let handshake: [String: Any] = ["v": 1, "client_id": clientID]
            try transport.writeFrame(opcode: .handshake, payload: try Self.jsonData(handshake))

            let (opcode, payload) = try transport.readFrame()
            guard opcode == DiscordOpcode.frame.rawValue else {
                throw DiscordIPCError.connectionClosed
            }

            if let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
               let evt = json["evt"] as? String, evt == "ERROR" {
                Log.error("Discord rejected handshake: \((json["data"] as? [String: Any])?["message"] as? String ?? "unknown error")")
                throw DiscordIPCError.connectionClosed
            }
        } catch {
            transport.close()
            throw error
        }
    }

    func setActivity(_ activity: DiscordActivity?) throws {
        var args: [String: Any] = ["pid": Int(ProcessInfo.processInfo.processIdentifier)]
        args["activity"] = activity?.jsonObject

        let command: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": args,
            "nonce": UUID().uuidString,
        ]

        try transport.writeFrame(opcode: .frame, payload: try Self.jsonData(command))

        _ = try? transport.readFrame()
    }

    func clearActivity() throws {
        try setActivity(nil)
    }

    func close() {
        guard transport.isConnected else { return }
        try? transport.writeFrame(opcode: .close, payload: Data())
        transport.close()
    }

    private static func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
}
