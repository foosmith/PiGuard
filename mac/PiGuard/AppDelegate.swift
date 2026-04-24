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
    func applicationDidFinishLaunching(_: Notification) {
        // Remove legacy v1 plaintext token that may be sitting in UserDefaults
        UserDefaults.standard.removeObject(forKey: "token")

        // Register Apple Event handler for piguard:// URLs.
        // application(_:open:urls:) is unreliable for LSUIElement agent apps;
        // the Apple Event manager fires reliably for all app types.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        #if !APPSTORE
        if Preferences.standard.automaticallyCheckForUpdates {
            UpdateManager.shared.checkForUpdatesInBackground()
        }
        #endif
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "piguard"
        else { return }
        Log.debug("URL event received: \(urlString)")
        NotificationCenter.default.post(name: .piGuardOpenQueryLog, object: nil)
    }

    func applicationWillTerminate(_: Notification) {
        // Remove the PID lockfile so the next launch doesn't see a stale entry.
        let pidURL = Log.logFileURL.deletingLastPathComponent()
            .appendingPathComponent("piguard.pid")
        try? FileManager.default.removeItem(at: pidURL)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Fallback for environments where Apple Events are not delivered.
        if urls.contains(where: { $0.scheme == "piguard" }) {
            Log.debug("application(_:open:urls:) received piguard:// URL")
            NotificationCenter.default.post(name: .piGuardOpenQueryLog, object: nil)
        }
    }

    public static func bringToFront(window: NSWindow) {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
