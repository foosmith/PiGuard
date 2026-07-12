//
//  DiagnosisMessageMonitor.swift
//  PiGuard
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import Cocoa
import UserNotifications

extension Notification.Name {
    /// Posted on the main thread whenever the set of Pi-hole diagnosis messages changes.
    static let piGuardDiagnosisMessagesUpdated = Notification.Name("PiGuard.DiagnosisMessages.Updated")
}

/// Polls Pi-hole v6 servers for FTL diagnosis messages (the yellow bell in the
/// web UI) and raises a macOS notification when new ones appear. All state is
/// confined to the main thread.
final class DiagnosisMessageMonitor: NSObject {
    struct ServerMessages {
        let identifier: String
        let displayName: String
        let api: Pihole6API
        let messages: [Pihole6API.DiagnosisMessage]
    }

    /// Messages change rarely; checking every poll cycle (default 3 s) would be
    /// wasteful, so checks run at most this often.
    private let checkInterval: TimeInterval = 300

    private var lastCheck: Date?
    private var isChecking = false

    private(set) var latest: [ServerMessages] = []

    var messageCount: Int {
        latest.reduce(0) { $0 + $1.messages.count }
    }

    /// Called from the manager's poll cycle (any thread). Runs a check at most
    /// once per `checkInterval`; the first call checks immediately.
    func checkIfDue(piholes: [Pihole]) {
        DispatchQueue.main.async {
            if let lastCheck = self.lastCheck, Date().timeIntervalSince(lastCheck) < self.checkInterval {
                return
            }
            self.check(piholes: piholes)
        }
    }

    /// Fetches messages from every v6 Pi-hole. Main thread only.
    private func check(piholes: [Pihole]) {
        guard !isChecking else { return }
        let v6Piholes = piholes.filter { $0.api6 != nil }
        guard !v6Piholes.isEmpty else { return }

        isChecking = true
        lastCheck = Date()

        Task { @MainActor [weak self] in
            var results: [ServerMessages] = []
            for pihole in v6Piholes {
                guard let api = pihole.api6 else { continue }
                if let messages = await api.fetchDiagnosisMessages() {
                    results.append(ServerMessages(
                        identifier: pihole.identifier,
                        displayName: pihole.displayName,
                        api: api,
                        messages: messages
                    ))
                } else if let previous = self?.latest.first(where: { $0.identifier == pihole.identifier }) {
                    // Fetch failed (offline?) — keep what we last knew for that server.
                    results.append(previous)
                }
            }
            guard let self else { return }
            self.isChecking = false
            self.latest = results
            self.notifyAboutNewMessages(in: results)
            NotificationCenter.default.post(name: .piGuardDiagnosisMessagesUpdated, object: nil)
        }
    }

    /// Deletes every current message on every server, then refreshes.
    func dismissAll() {
        let snapshot = latest
        Task { @MainActor [weak self] in
            var results: [ServerMessages] = []
            for server in snapshot {
                for message in server.messages {
                    _ = await server.api.deleteDiagnosisMessage(id: message.id)
                }
                let remaining = await server.api.fetchDiagnosisMessages() ?? []
                results.append(ServerMessages(
                    identifier: server.identifier,
                    displayName: server.displayName,
                    api: server.api,
                    messages: remaining
                ))
            }
            guard let self else { return }
            self.latest = results
            // Deleted messages should not re-notify if FTL recreates them later
            // with new IDs, so re-sync the persisted set too.
            self.notifyAboutNewMessages(in: results)
            NotificationCenter.default.post(name: .piGuardDiagnosisMessagesUpdated, object: nil)
        }
    }

    // MARK: - Notifications

    private func notifyAboutNewMessages(in results: [ServerMessages]) {
        var notified = Preferences.standard.notifiedDiagnosisMessageIDs
        var newMessages: [(server: String, message: Pihole6API.DiagnosisMessage)] = []

        for server in results {
            let seen = Set(notified[server.identifier] ?? [])
            let unseen = server.messages.filter { !seen.contains($0.id) }
            newMessages.append(contentsOf: unseen.map { (server.displayName, $0) })
            // Persist the full current set so dismissed messages drop out.
            notified[server.identifier] = server.messages.map(\.id)
        }
        Preferences.standard.set(notifiedDiagnosisMessageIDs: notified)

        guard !newMessages.isEmpty else { return }
        Log.info("Diagnosis monitor: \(newMessages.count) new message(s)")
        // Seen IDs are persisted above even when notifications are off, so
        // re-enabling later never replays old messages.
        guard Preferences.standard.diagnosisNotificationsEnabled else { return }
        deliverNotification(for: newMessages)
    }

    private func deliverNotification(for newMessages: [(server: String, message: Pihole6API.DiagnosisMessage)]) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.warn("Diagnosis monitor: notification authorization failed: \(error)")
                return
            }
            guard granted else { return }

            let content = UNMutableNotificationContent()
            if newMessages.count == 1, let item = newMessages.first {
                content.title = "Pi-hole: \(item.server)"
                content.body = item.message.plain
            } else {
                content.title = "Pi-hole Diagnosis Messages"
                let servers = Set(newMessages.map(\.server)).sorted().joined(separator: ", ")
                content.body = "\(newMessages.count) new messages on \(servers)"
            }
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "PiGuard.diagnosis.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request) { error in
                if let error {
                    Log.warn("Diagnosis monitor: failed to deliver notification: \(error)")
                }
            }
        }
    }
}

extension DiagnosisMessageMonitor: UNUserNotificationCenterDelegate {
    // Show banners even while PiGuard is the active app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
