//
//  main.swift
//  xcord
//

import AppKit
import ApplicationServices
import Foundation

_ = NSWorkspace.shared
_ = AXIsProcessTrusted()

let config = ConfigStore.load()
print("Loaded config: \(config)")

