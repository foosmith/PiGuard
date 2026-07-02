//
//  WidgetSnapshotStore.swift
//  PiGuard
//
//  Shared between the PiGuard main app target and the PiGuardWidget extension target.
//  Must not import AppKit or Cocoa.
//
//  Primary channel: App Group shared file container. The group ID is team-prefixed
//    (not "group."-prefixed) — on macOS the team-prefixed form is authorized by the
//    code signature alone, so the sandboxed widget can read it without a
//    provisioning profile. The iOS-style "group." prefix requires provisioning
//    profile authorization on macOS 15+, which Developer ID builds don't have.
//  Secondary channel: NSDistributedNotificationCenter push from main app to widget.
//    Notification name MUST start with the widget's bundle ID so the sandboxed
//    widget extension is allowed to receive it (macOS sandbox restriction).
//  Tertiary channel: widget's own UserDefaults local cache.

import Foundation

enum WidgetSnapshotStore {
    static let appGroupID = "GB7Z2TZ8LT.com.foosmith.PiGuard"
    // Must start with widget bundle ID for sandbox-restricted DistributedNotificationCenter delivery.
    static let distributedNotificationName = "com.foosmith.PiGuard.PiGuardWidget.snapshot"
    static let snapshotRequestNotificationName = "com.foosmith.PiGuard.PiGuardWidget.snapshotRequest"
    private static let localCacheKey = "com.foosmith.PiGuard.cachedSnapshot"

    // MARK: - App Group file (primary)

    private static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("widget_snapshot.json")
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = snapshotURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    // MARK: - Local UserDefaults cache (fallback — widget's own container)

    static func writeLocalCache(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: localCacheKey)
    }

    static func readLocalCache() -> WidgetSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: localCacheKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    // MARK: - Best available

    /// Returns the freshest snapshot across all channels, so one channel gone
    /// stale (or frozen by a failed writer) can never mask newer data in another.
    static func readBest() -> WidgetSnapshot? {
        [read(), readLocalCache()]
            .compactMap { $0 }
            .max { $0.updatedAt < $1.updatedAt }
    }
}
