//
//  WidgetSnapshotStore.swift
//  PiGuard
//
//  Shared between the PiGuard main app target and the PiGuardWidget extension target.
//  Must not import AppKit or Cocoa.
//
//  Primary channel: App Group shared file container (works when both targets are fully
//  provisioned with the App Group capability).
//  Fallback channel: NSDistributedNotificationCenter — the main app broadcasts the
//  snapshot as JSON; the widget caches it in its own UserDefaults.standard.

import Foundation

enum WidgetSnapshotStore {
    static let appGroupID = "group.com.foosmith.PiGuard"
    static let distributedNotificationName = "com.foosmith.PiGuard.widgetSnapshot"
    private static let localCacheKey = "com.foosmith.PiGuard.cachedSnapshot"

    private static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("widget_snapshot.json")
    }

    // MARK: - App Group file (primary)

    /// Called by the main app after each stats update.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = snapshotURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Read from the App Group shared file. Returns nil if the file is inaccessible.
    static func read() -> WidgetSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    // MARK: - Local UserDefaults cache (fallback for widget extension)

    /// Saves snapshot to the widget extension's own UserDefaults (no App Group needed).
    static func writeLocalCache(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: localCacheKey)
    }

    /// Reads the last snapshot cached via distributed notification.
    static func readLocalCache() -> WidgetSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: localCacheKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    // MARK: - Best available

    /// Returns the freshest snapshot from whichever source is accessible.
    static func readBest() -> WidgetSnapshot? {
        read() ?? readLocalCache()
    }
}
