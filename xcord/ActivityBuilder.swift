//
//  ActivityBuilder.swift
//  xcord
//

import Foundation

enum ActivityBuilder {
    static func buildActivity(
        document: XcodeDocument?,
        config: XcordConfig,
        startTimestamp: Date
    ) -> DiscordActivity {
        guard !config.privacyMode, let document else {
            return DiscordActivity(
                details: "Using Xcode",
                state: nil,
                startTimestamp: startTimestamp,
                largeImageKey: AssetMap.genericFallback,
                largeImageText: "Xcode",
                smallImageKey: nil,
                smallImageText: nil
            )
        }

        let (titleProject, titleItem) = parseTitle(document.title)
        let filename = document.path.map { ($0 as NSString).lastPathComponent } ?? titleItem
        let projectName = titleProject

        let details: String?
        if config.showFilename, let filename {
            details = "Editing \(filename)"
        } else {
            details = "Using Xcode"
        }

        let state: String?
        if config.showProjectName, let projectName {
            state = "in \(projectName)"
        } else {
            state = nil
        }

        let assetKey = filename.map { AssetMap.assetKey(forPath: $0, overrides: config.iconAssetOverrides) } ?? AssetMap.genericFallback

        return DiscordActivity(
            details: details,
            state: state,
            startTimestamp: startTimestamp,
            largeImageKey: assetKey,
            largeImageText: filename ?? "Xcode",
            smallImageKey: "xcode-icon",
            smallImageText: "Xcode"
        )
    }

    private static func parseTitle(_ title: String) -> (project: String?, item: String?) {
        let separator = " — "
        guard let range = title.range(of: separator) else {
            return (nil, title.isEmpty ? nil : title)
        }

        let project = String(title[title.startIndex..<range.lowerBound])
        let item = String(title[range.upperBound...])
        return (project.isEmpty ? nil : project, item.isEmpty ? nil : item)
    }
}
