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
import WidgetKit

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
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Remove legacy v1 plaintext token that may be sitting in UserDefaults
        UserDefaults.standard.removeObject(forKey: "token")

        refreshWidgetProcessAfterUpdateIfNeeded()

        #if !APPSTORE
        if Preferences.standard.automaticallyCheckForUpdates {
            UpdateManager.shared.checkForUpdatesInBackground()
        }
        #endif
    }

    // MARK: - Widget Process Refresh After Update

    /// Replacing the app bundle on disk does not restart an already-running
    /// widget extension process. The orphaned process keeps serving its last
    /// timeline — and once the app bundle underneath it changed, it can no
    /// longer read the App Group container, so the widget freezes on
    /// "App not running · cached" until the process dies. On the first launch
    /// of a new build, terminate any running PiGuardWidget process (WidgetKit
    /// respawns it from the new bundle) and ask for a timeline reload.
    private func refreshWidgetProcessAfterUpdateIfNeeded() {
        let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard !currentBuild.isEmpty, Preferences.standard.lastRunBuild != currentBuild else { return }
        Log.debug("First launch of build \(currentBuild) (was \(Preferences.standard.lastRunBuild)); refreshing widget process")
        Preferences.standard.set(lastRunBuild: currentBuild)

        #if !APPSTORE
        terminateStaleWidgetProcesses()
        #endif

        // Give a terminated process a moment to exit so chronod doesn't hand
        // the reload to the dying instance. Harmless if nothing was killed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    #if !APPSTORE
    /// Sends SIGTERM to running PiGuardWidget.appex processes. Only possible
    /// in the non-sandboxed Developer ID build; the sandboxed App Store build
    /// compiles this out (signalling other processes is denied there, and App
    /// Store installs re-register extensions through installd anyway).
    private func terminateStaleWidgetProcesses() {
        var pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return }
        var pids = [pid_t](repeating: 0, count: Int(pidCount) * 2)
        pidCount = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard pidCount > 0 else { return }

        for pid in pids.prefix(Int(pidCount)) where pid > 0 {
            var pathBuffer = [CChar](repeating: 0, count: 4096)
            guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else { continue }
            let path = String(cString: pathBuffer)
            if path.contains("/PiGuardWidget.appex/") {
                Log.debug("Terminating stale widget process \(pid) at \(path)")
                kill(pid, SIGTERM)
            }
        }
    }
    #endif

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
        if urls.contains(where: { $0.scheme == "piguard" }) {
            Log.debug("application(_:open:urls:) received piguard:// URL")
            NotificationCenter.default.post(name: .piGuardOpenQueryLog, object: nil)
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
        // NSApp.windows includes the status item's own NSStatusBarWindow, which is
        // always visible (level .statusBar) — only user-facing normal-level windows
        // should keep the app in the Dock.
        let hasVisibleWindows = NSApp.windows.contains { $0.isVisible && $0.level == .normal }
        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
