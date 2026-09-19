//
//  Activity.swift
//  xcord
//

import Foundation

struct DiscordActivity {
    var details: String?
    var state: String?
    var startTimestamp: Date?
    var largeImageKey: String?
    var largeImageText: String?
    var smallImageKey: String?
    var smallImageText: String?

    var jsonObject: [String: Any] {
        var object: [String: Any] = [:]

        if let details { object["details"] = details }
        if let state { object["state"] = state }

        if let startTimestamp {
            object["timestamps"] = ["start": Int(startTimestamp.timeIntervalSince1970)]
        }

        var assets: [String: Any] = [:]
        if let largeImageKey { assets["large_image"] = largeImageKey }
        if let largeImageText { assets["large_text"] = largeImageText }
        if let smallImageKey { assets["small_image"] = smallImageKey }
        if let smallImageText { assets["small_text"] = smallImageText }
        if !assets.isEmpty { object["assets"] = assets }

        return object
    }
}
