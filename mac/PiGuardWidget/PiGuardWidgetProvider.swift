//
//  PiGuardWidgetProvider.swift
//  PiGuardWidget

import WidgetKit
import Foundation

struct PiGuardWidgetProvider: TimelineProvider {
    typealias Entry = PiGuardWidgetEntry

    /// Snapshot older than this renders the "App not running · cached" warning.
    private static let cachedWarningAge: TimeInterval = 1200

    func placeholder(in context: Context) -> PiGuardWidgetEntry {
        PiGuardWidgetEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PiGuardWidgetEntry) -> Void) {
        completion(PiGuardWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.readBest()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PiGuardWidgetEntry>) -> Void) {
        func finish(with snapshot: WidgetSnapshot?) {
            let now = Date()
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: now)!
            var entries: [PiGuardWidgetEntry] = []

            if let snapshot {
                let warnDate = snapshot.updatedAt.addingTimeInterval(Self.cachedWarningAge)
                if warnDate > now {
                    entries.append(PiGuardWidgetEntry(date: now, snapshot: snapshot))
                    // Pre-schedule the warning so it appears even if WidgetKit
                    // throttles the next reload — no getTimeline run needed.
                    entries.append(PiGuardWidgetEntry(date: warnDate, snapshot: snapshot, showsCachedWarning: true))
                } else {
                    entries.append(PiGuardWidgetEntry(date: now, snapshot: snapshot, showsCachedWarning: true))
                }
            } else {
                entries.append(PiGuardWidgetEntry(date: now, snapshot: nil))
            }

            completion(Timeline(entries: entries, policy: .after(next)))
        }

        // Fast path: use stored data when it's fresh (main app is actively running
        // and the widget can read the App Group file it publishes to).
        if let snapshot = WidgetSnapshotStore.readBest(), !isStale(snapshot.updatedAt) {
            finish(with: snapshot)
            return
        }

        // Slow path: request a snapshot from the main app and wait up to 5 s.
        // The main app embeds the full JSON payload in the notification's userInfo,
        // so this works even if the App Group file can't be read.
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
