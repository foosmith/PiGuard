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

        // Fast path: Keychain or cached data already available.
        if let snapshot = WidgetSnapshotStore.readBest() {
            finish(with: snapshot)
            return
        }

        // Slow path: PiGuard hasn't polled yet. Wait up to 5 s for it to broadcast
        // via NSDistributedNotificationCenter, then cache in local UserDefaults.
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

        // Ask the main app to send the snapshot now.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(WidgetSnapshotStore.snapshotRequestNotificationName),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        DispatchQueue.global(qos: .userInitiated).async {
            _ = sem.wait(timeout: .now() + 5)
            DistributedNotificationCenter.default().removeObserver(token)
            finish(with: received)
        }
    }
}
