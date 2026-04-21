//
//  PiGuardWidgetProvider.swift
//  PiGuardWidget

import WidgetKit
import Foundation

struct PiGuardWidgetProvider: TimelineProvider {
    typealias Entry = PiGuardWidgetEntry

    func placeholder(in context: Context) -> PiGuardWidgetEntry {
        PiGuardWidgetEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PiGuardWidgetEntry) -> Void) {
        completion(PiGuardWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PiGuardWidgetEntry>) -> Void) {
        let entry = PiGuardWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.read())
        // Fallback refresh every 15 minutes; the main app pushes reloads via
        // WidgetCenter.shared.reloadAllTimelines() on every polling cycle.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}
