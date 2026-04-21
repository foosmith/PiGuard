//
//  WidgetSnapshotStore.swift
//  PiGuard
//
//  Shared between the PiGuard main app target and the PiGuardWidget extension target.
//  Must not import AppKit or Cocoa.
//
//  Uses the App Group shared file container rather than UserDefaults(suiteName:),
//  which has a known CFPrefs limitation on macOS that prevents cross-process sharing.

import Foundation

enum WidgetSnapshotStore {
    static let appGroupID = "group.com.foosmith.PiGuard"

    private static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("widget_snapshot.json")
    }

    /// Called by the main app after each stats update.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = snapshotURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Called by the widget extension's TimelineProvider.
    static func read() -> WidgetSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
