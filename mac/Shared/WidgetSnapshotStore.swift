//
//  WidgetSnapshotStore.swift
//  PiGuard
//
//  Shared between the PiGuard main app target and the PiGuardWidget extension target.
//  Must not import AppKit or Cocoa.

import Foundation

enum WidgetSnapshotStore {
    static let appGroupID = "group.com.foosmith.PiGuard"
    static let key = "com.foosmith.PiGuard.widgetSnapshot"

    /// Called by the main app after each stats update.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    /// Called by the widget extension's TimelineProvider.
    static func read() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
