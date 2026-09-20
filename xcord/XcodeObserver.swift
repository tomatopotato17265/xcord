//
//  XcodeObserver.swift
//  xcord
//

import AppKit
import ApplicationServices
import Foundation

struct XcodeDocument: Equatable {
    var path: String?
    var title: String
}

enum XcodeObserverError: Error {
    case observerCreationFailed(AXError)
    case notificationRegistrationFailed(AXError)
}

final class XcodeObserver {
    private let pid: pid_t
    private let appElement: AXUIElement
    private var axObserver: AXObserver?
    private var observedWindowElement: AXUIElement?
    var onDocumentChange: ((XcodeDocument?) -> Void)?

    init(xcode: NSRunningApplication) {
        self.pid = xcode.processIdentifier
        self.appElement = AXUIElementCreateApplication(pid)
    }

    func start() throws {
        var observer: AXObserver?
        let createResult = AXObserverCreate(pid, XcodeObserver.axCallback, &observer)
        guard createResult == .success, let observer else {
            throw XcodeObserverError.observerCreationFailed(createResult)
        }
        axObserver = observer

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let addResult = AXObserverAddNotification(
            observer, appElement, kAXFocusedWindowChangedNotification as CFString, refcon
        )
        guard addResult == .success || addResult == .notificationAlreadyRegistered else {
            throw XcodeObserverError.notificationRegistrationFailed(addResult)
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)

        observeFocusedWindow(reportChange: true)
    }

    func stop() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observedWindowElement = nil
        axObserver = nil
    }

    func currentDocument() -> XcodeDocument? {
        guard let window = focusedWindow() else { return nil }
        return document(forWindow: window)
    }

    // MARK: - Focused window tracking

    private func observeFocusedWindow(reportChange: Bool) {
        guard let observer = axObserver else { return }

        if let previousWindow = observedWindowElement {
            AXObserverRemoveNotification(observer, previousWindow, kAXTitleChangedNotification as CFString)
        }
        observedWindowElement = nil

        guard let window = focusedWindow() else {
            if reportChange { onDocumentChange?(nil) }
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString, refcon)
        if result == .success || result == .notificationAlreadyRegistered {
            observedWindowElement = window
        }

        if reportChange {
            onDocumentChange?(document(forWindow: window))
        }
    }

    private func document(forWindow window: AXUIElement) -> XcodeDocument {
        let title = (copyAttribute(window, kAXTitleAttribute) as? String) ?? ""

        if let documentURLString = copyAttribute(window, kAXDocumentAttribute) as? String,
           let url = URL(string: documentURLString), url.isFileURL {
            return XcodeDocument(path: url.path, title: title)
        }

        return XcodeDocument(path: nil, title: title)
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    private func focusedWindow() -> AXUIElement? {
        guard let value = copyAttribute(appElement, kAXFocusedWindowAttribute) else { return nil }
        return (value as! AXUIElement)
    }

    // MARK: - C callback bridging

    private static let axCallback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let observerInstance = Unmanaged<XcodeObserver>.fromOpaque(refcon).takeUnretainedValue()
        observerInstance.handle(notification: notification as String, element: element)
    }

    private func handle(notification: String, element: AXUIElement) {
        switch notification {
        case kAXFocusedWindowChangedNotification:
            observeFocusedWindow(reportChange: true)
        case kAXTitleChangedNotification:
            onDocumentChange?(document(forWindow: element))
        default:
            break
        }
    }

    deinit {
        stop()
    }
}
