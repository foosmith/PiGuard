//
//  AppDelegate.swift
//  PiGuard
//
//  Created by Brad Root on 5/17/20.
//  Copyright © 2020 Brad Root. All rights reserved.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_: Notification) {
        // Register the Apple Event URL handler as early as possible. If we wait
        // until applicationDidFinishLaunching, a URL delivered during launch
        // arrives before the handler is installed and is lost.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        _trace("AppDelegate.applicationWillFinishLaunching — registered AppleEvent URL handler")
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Remove legacy v1 plaintext token that may be sitting in UserDefaults
        UserDefaults.standard.removeObject(forKey: "token")
        _trace("AppDelegate.applicationDidFinishLaunching")

        #if !APPSTORE
        if Preferences.standard.automaticallyCheckForUpdates {
            UpdateManager.shared.checkForUpdatesInBackground()
        }
        #endif
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
        let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue ?? "<nil>"
        _trace("AppDelegate.handleGetURLEvent — raw=\(raw)")
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "piguard"
        else {
            _trace("AppDelegate.handleGetURLEvent — rejected (not piguard scheme)")
            return
        }
        Log.debug("URL event received: \(urlString)")
        NotificationCenter.default.post(name: .piGuardOpenQueryLog, object: nil)
        _trace("AppDelegate.handleGetURLEvent — posted .piGuardOpenQueryLog")
    }

    func applicationWillTerminate(_: Notification) {
        // Remove the PID lockfile so the next launch doesn't see a stale entry.
        let pidURL = Log.logFileURL.deletingLastPathComponent()
            .appendingPathComponent("piguard.pid")
        try? FileManager.default.removeItem(at: pidURL)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        _trace("AppDelegate.application(_:open:urls:) — urls=\(urls.map { $0.absoluteString })")
        if urls.contains(where: { $0.scheme == "piguard" }) {
            Log.debug("application(_:open:urls:) received piguard:// URL")
            NotificationCenter.default.post(name: .piGuardOpenQueryLog, object: nil)
            _trace("AppDelegate.application(_:open:urls:) — posted .piGuardOpenQueryLog")
        }
    }

    public static func bringToFront(window: NSWindow) {
        // Switch to regular policy so the window can steal focus reliably on macOS 14+.
        // Accessory-policy apps (LSUIElement) can no longer use activate(ignoringOtherApps:)
        // reliably. The policy reverts to .accessory when all windows close.
        NSApp.setActivationPolicy(.regular)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public static func revertToAccessoryPolicyIfNeeded() {
        let hasVisibleWindows = NSApp.windows.contains { $0.isVisible }
        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
