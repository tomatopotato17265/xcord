//
//  Permissions.swift
//  xcord
//

import ApplicationServices
import Foundation

enum Permissions {
    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options: [String: Bool] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func logMissingAccessibilityPermission() {
        Log.error(
            "Accessibility permission is not granted. xcord can't read the current Xcode document without it. " +
            "Grant it via System Settings > Privacy & Security > Accessibility, then relaunch xcord."
        )
    }
}
