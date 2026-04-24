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

        // Slow path: Wait up to 5s for the main app to update the secure store
        // and send a 'ping' notification.
        let sem = DispatchSemaphore(value: 0)
        let notifQueue = OperationQueue()

        let token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(WidgetSnapshotStore.distributedNotificationName),
            object: nil,
            queue: notifQueue
        ) { _ in
            sem.signal()
        }

        // Ask the main app to update the snapshot and notify us.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(WidgetSnapshotStore.snapshotRequestNotificationName),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        DispatchQueue.global(qos: .userInitiated).async {
            _ = sem.wait(timeout: .now() + 5)
            DistributedNotificationCenter.default().removeObserver(token)
            
            // Re-read from the secure store now that we've been signaled (or timed out)
            finish(with: WidgetSnapshotStore.readBest())
        }
    }
}
