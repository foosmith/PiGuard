//
//  OpenQueryLogIntent.swift
//  PiGuard (main app) + PiGuardWidget (extension)
//
//  AppIntent that signals the main app to open its Query Log window.
//
//  This file is compiled into BOTH targets:
//
//  • Main app target  — on macOS with openAppWhenRun = true, the system routes
//    the intent here and calls perform() in the main app process. The local
//    NotificationCenter post is received immediately by MainMenuController.
//
//  • Widget extension — perform() may also run here (e.g. when the app is not
//    running). The DistributedNotificationCenter post crosses the sandbox
//    boundary to reach the main app. The App Group flag file is consumed at
//    next launch if the app was not yet running.

import AppIntents
import Foundation

@available(macOS 13.0, *)
struct OpenQueryLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Query Log"

    // true → macOS routes the intent to the main app process and activates the
    // app window. Required for perform() to actually be dispatched on macOS.
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Path 1: Running in the main app process.
        // AppIntents calls perform() on a background cooperative queue; dispatch
        // to MainActor so that handleOpenQueryLog() can safely touch AppKit UI.
        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("com.foosmith.PiGuard.openQueryLog"),
                object: nil
            )
        }

        // Path 2: Running in the widget extension process (fallback).
        // DistributedNotificationCenter crosses the sandbox boundary via distnoted.
        // Also received by the main app if perform() happens to run there.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.foosmith.PiGuard.openQueryLog"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        // Path 3: App not running — flag file consumed by startFlagFileWatcher()
        // or at next launch.
        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.foosmith.PiGuard") {
            let flagURL = groupURL.appendingPathComponent("open_query_log.flag")
            try? "1".write(to: flagURL, atomically: true, encoding: .utf8)
        }

        return .result()
    }
}
