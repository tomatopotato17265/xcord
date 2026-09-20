//
//  main.swift
//  xcord
//

import AppKit
import ApplicationServices
import Foundation


guard let xcode = XcodeProcessTracker.runningXcode() else {
    Log.info("Xcode is not running — exiting.")
    exit(0)
}

guard Permissions.hasAccessibilityPermission(prompt: false) else {
    Permissions.logMissingAccessibilityPermission()
    exit(1)
}

let config = ConfigStore.load()
guard config.discordClientID != XcordConfig.placeholderClientID else {
    Log.error("Discord client ID is not configured — set it in the config file and relaunch xcord.")
    exit(1)
}

let sessionStart = Date()
let discord = DiscordIPC(clientID: config.discordClientID)

do {
    try discord.connect()
    Log.info("Connected to Discord.")
} catch {
    Log.error("Failed to connect to Discord: \(error)")
    exit(1)
}

func publish(_ document: XcodeDocument?) {
    let activity = ActivityBuilder.buildActivity(document: document, config: config, startTimestamp: sessionStart)
    do {
        try discord.setActivity(activity)
    } catch {
        Log.error("Failed to set activity: \(error)")
    }
}

let observer = XcodeObserver(xcode: xcode)
observer.onDocumentChange = { document in
    publish(document)
}

do {
    try observer.start()
    Log.info("Watching Xcode for document changes.")
} catch {
    Log.error("Failed to start XcodeObserver: \(error)")
    exit(1)
}

publish(observer.currentDocument())

let lifecycleWatcher = XcodeLifecycleWatcher(xcode: xcode)
lifecycleWatcher.onTerminate = {
    Log.info("Xcode quit — shutting down.")
    try? discord.clearActivity()
    discord.close()
    exit(0)
}

CFRunLoopRun()
