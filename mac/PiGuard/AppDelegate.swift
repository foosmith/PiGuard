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

        #if !APPSTORE
        if Preferences.standard.automaticallyCheckForUpdates {
            UpdateManager.shared.checkForUpdatesInBackground()
        }
        #endif
    }

    func applicationWillTerminate(_: Notification) {
        // Insert code here to tear down your application
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NSApp.activate(ignoringOtherApps: true)
    }

    public static func bringToFront(window: NSWindow) {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
