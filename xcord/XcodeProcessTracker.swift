//
//  XcodeProcessTracker.swift
//  xcord
//

import AppKit
import Foundation

enum XcodeProcessTracker {
    static let bundleIdentifier = "com.apple.dt.Xcode"
    
    static func runningXcode() -> NSRunningApplication? {
        let candidates = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleIdentifier
        }

        if candidates.count > 1, let frontmost = candidates.first(where: { $0.isActive }) {
            return frontmost
        }

        return candidates.first
    }

    static func isXcodeRunning() -> Bool {
        runningXcode() != nil
    }
}

final class XcodeLifecycleWatcher {
    private let pid: pid_t
    private var terminationObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var deactivationObserver: NSObjectProtocol?

    var onTerminate: (() -> Void)?
    var onFrontmostChange: ((Bool) -> Void)?

    init(xcode: NSRunningApplication) {
        self.pid = xcode.processIdentifier
        let center = NSWorkspace.shared.notificationCenter

        terminationObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, self.matches(notification) else { return }
            self.onTerminate?()
        }

        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.onFrontmostChange?(self.matches(notification))
        }

        deactivationObserver = center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, self.matches(notification) else { return }
            self.onFrontmostChange?(false)
        }
    }

    private func matches(_ notification: Notification) -> Bool {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return false
        }
        return app.processIdentifier == pid
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        [terminationObserver, activationObserver, deactivationObserver].forEach { observer in
            if let observer { center.removeObserver(observer) }
        }
    }
}
