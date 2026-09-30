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

// MARK: - Discord connection with reconnect/backoff

var isDiscordConnected = false
var reconnectDelay: TimeInterval = 1
let maxReconnectDelay: TimeInterval = 30
var reconnectTimer: Timer?
var pendingActivity: DiscordActivity?
var hasLoggedDisconnected = false

func scheduleReconnect() {
    isDiscordConnected = false
    reconnectTimer?.invalidate()

    let delay = reconnectDelay
    reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)

    reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
        connectToDiscord()
    }
}

func connectToDiscord() {
    do {
        try discord.connect()
        isDiscordConnected = true
        hasLoggedDisconnected = false
        reconnectDelay = 1
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        Log.info("Connected to Discord.")

        if let pendingActivity {
            try? discord.setActivity(pendingActivity)
        }
    } catch {
        if !hasLoggedDisconnected {
            Log.warn("Discord isn't reachable yet (\(error)) — will keep retrying quietly.")
            hasLoggedDisconnected = true
        }
        scheduleReconnect()
    }
}

func publish(_ document: XcodeDocument?) {
    let activity = ActivityBuilder.buildActivity(document: document, config: config, startTimestamp: sessionStart)
    pendingActivity = activity

    guard isDiscordConnected else { return }

    do {
        try discord.setActivity(activity)
    } catch {
        Log.warn("Lost connection to Discord while setting activity (\(error)) — reconnecting.")
        scheduleReconnect()
    }
}

connectToDiscord()

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
    reconnectTimer?.invalidate()
    try? discord.clearActivity()
    discord.close()
    exit(0)
}

CFRunLoopRun()
