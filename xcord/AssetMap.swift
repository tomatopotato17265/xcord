//
//  AssetMap.swift
//  xcord
//

import Foundation

enum AssetMap {
    static let genericFallback = "xcode-icon"

    private static let extensionToAssetKey: [String: String] = [
        "swift": "swift",
        "m": "objc",
        "mm": "objcpp",
        "h": "header",
        "hpp": "header",
        "c": "c",
        "cpp": "cpp",
        "cc": "cpp",
        "storyboard": "storyboard",
        "xib": "interface-builder",
        "plist": "plist",
        "entitlements": "plist",
        "md": "markdown",
        "markdown": "markdown",
        "json": "json",
        "yml": "yaml",
        "yaml": "yaml",
        "metal": "metal",
        "xcodeproj": "xcode-icon",
        "xcworkspace": "xcode-icon",
        "xcconfig": "xcode-icon",
        "pbxproj": "xcode-icon",
        "sh": "shell",
        "py": "python",
        "rb": "ruby",
        "xcassets": "assets",
    ]

    static func assetKey(forPath path: String, overrides: [String: String]? = nil) -> String {
        let ext = (path as NSString).pathExtension.lowercased()

        if let overrides, let overridden = overrides[ext] {
            return overridden
        }

        return extensionToAssetKey[ext] ?? genericFallback
    }
}
