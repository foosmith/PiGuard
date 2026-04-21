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
        completion(PiGuardWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.readBest()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PiGuardWidgetEntry>) -> Void) {
        func finish(with snapshot: WidgetSnapshot?) {
            let entry = PiGuardWidgetEntry(date: Date(), snapshot: snapshot)
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }

        // Fast path: App Group file or local cache already has data.
        if let snapshot = WidgetSnapshotStore.readBest() {
            finish(with: snapshot)
            return
        }

        // Slow path: wait up to 5 s for the main app to broadcast a snapshot via
        // NSDistributedNotificationCenter (used when App Group file access is blocked).
        let sem = DispatchSemaphore(value: 0)
        var received: WidgetSnapshot?
        let notifQueue = OperationQueue()

        let token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(WidgetSnapshotStore.distributedNotificationName),
            object: nil,
            queue: notifQueue
        ) { note in
            if let json = note.userInfo?["json"] as? String,
               let data = json.data(using: .utf8),
               let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
                WidgetSnapshotStore.writeLocalCache(snap)
                received = snap
            }
            sem.signal()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            _ = sem.wait(timeout: .now() + 5)
            DistributedNotificationCenter.default().removeObserver(token)
            finish(with: received)
        }
    }
}
