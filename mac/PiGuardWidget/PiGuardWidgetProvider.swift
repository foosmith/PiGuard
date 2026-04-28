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

        // Fast path: use cached data only when it's fresh (main app is actively running).
        if let snapshot = WidgetSnapshotStore.readBest(), !isStale(snapshot.updatedAt) {
            finish(with: snapshot)
            return
        }

        // Slow path: request a snapshot from the main app and wait up to 5 s.
        // The main app embeds the full JSON payload in the notification's userInfo,
        // so we don't rely on any shared storage channel (keychain or App Group).
        let sem = DispatchSemaphore(value: 0)
        let notifQueue = OperationQueue()
        var received: WidgetSnapshot?

        let token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(WidgetSnapshotStore.distributedNotificationName),
            object: nil,
            queue: notifQueue
        ) { notification in
            if let json = notification.userInfo?["json"] as? String,
               let data = json.data(using: .utf8),
               let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
                received = snapshot
                WidgetSnapshotStore.writeLocalCache(snapshot)
            }
            sem.signal()
        }

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(WidgetSnapshotStore.snapshotRequestNotificationName),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        DispatchQueue.global(qos: .userInitiated).async {
            _ = sem.wait(timeout: .now() + 5)
            DistributedNotificationCenter.default().removeObserver(token)
            finish(with: received ?? WidgetSnapshotStore.readBest())
        }
    }
}
