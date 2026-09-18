//
//  Config.swift
//  xcord
//

import Foundation

struct XcordConfig: Codable {
    var discordClientID: String
    var showFilename: Bool
    var showProjectName: Bool
    var privacyMode: Bool
    var iconAssetOverrides: [String: String]?

    static let placeholderClientID = "YOUR_DISCORD_CLIENT_ID"

    static let `default` = XcordConfig(
        discordClientID: placeholderClientID,
        showFilename: true,
        showProjectName: true,
        privacyMode: false,
        iconAssetOverrides: nil
    )
}

enum ConfigStore {
    private static var directoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("xcord", isDirectory: true)
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent("config.json")
    }
    
    static func load() -> XcordConfig {
        let fm = FileManager.default

        if let data = try? Data(contentsOf: fileURL),
           let config = try? JSONDecoder().decode(XcordConfig.self, from: data) {
            if config.discordClientID == XcordConfig.placeholderClientID {
                Log.warn("Discord client ID is not configured yet — edit \(fileURL.path) with your Discord application's client ID.")
            }
            return config
        }

        do {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder.xcordPretty.encode(XcordConfig.default)
            try data.write(to: fileURL, options: .atomic)
            Log.info("Wrote default config to \(fileURL.path) — edit it with your Discord application's client ID before running xcord.")
        } catch {
            Log.error("Failed to write default config at \(fileURL.path): \(error)")
        }

        return XcordConfig.default
    }
}

private extension JSONEncoder {
    static var xcordPretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
