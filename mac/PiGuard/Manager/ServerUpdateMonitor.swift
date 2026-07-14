//
//  ServerUpdateMonitor.swift
//  PiGuard
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//

import Cocoa

extension Notification.Name {
    /// Posted on the main thread whenever the set of available server updates changes.
    static let piGuardServerUpdatesUpdated = Notification.Name("PiGuard.ServerUpdates.Updated")
}

/// Polls Pi-hole v6 and AdGuard Home servers for available server-software
/// updates. AdGuard Home can also install its own update through the API;
/// Pi-hole cannot, so its menu action opens the web admin instead. All state
/// is confined to the main thread.
final class ServerUpdateMonitor: NSObject {
    struct ServerUpdates {
        let identifier: String
        let displayName: String
        /// Human-readable pending updates ("Core v6.0 → v6.1"); empty = up to date.
        let updates: [String]
        /// True when the server can install the update itself (AdGuard Home only).
        let canSelfUpdate: Bool
        let adguardAPI: AdGuardHomeAPI?
    }

    /// Servers publish releases rarely, and AdGuard caches its own version
    /// check server-side, so checks run at most this often.
    private let checkInterval: TimeInterval = 6 * 60 * 60

    private var lastCheck: Date?
    private var isChecking = false

    private(set) var latest: [ServerUpdates] = []

    var serversWithUpdates: [ServerUpdates] {
        latest.filter { !$0.updates.isEmpty }
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

    /// Forgets the check timestamp so the next poll cycle re-checks, e.g.
    /// after an in-place server update was started.
    func invalidate() {
        DispatchQueue.main.async {
            self.lastCheck = nil
        }
    }

    /// Fetches update availability from every v6 Pi-hole and AdGuard Home
    /// server. Main thread only.
    private func check(piholes: [Pihole]) {
        guard !isChecking else { return }
        let candidates = piholes.filter { $0.api6 != nil || $0.apiAdguard != nil }
        guard !candidates.isEmpty else { return }

        isChecking = true
        lastCheck = Date()

        Task { @MainActor [weak self] in
            var results: [ServerUpdates] = []
            for pihole in candidates {
                if let api6 = pihole.api6 {
                    if let updates = await api6.fetchAvailableUpdates() {
                        results.append(ServerUpdates(
                            identifier: pihole.identifier,
                            displayName: pihole.displayName,
                            updates: updates,
                            canSelfUpdate: false,
                            adguardAPI: nil
                        ))
                    } else if let previous = self?.latest.first(where: { $0.identifier == pihole.identifier }) {
                        // Fetch failed (offline?) — keep what we last knew.
                        results.append(previous)
                    }
                } else if let adguard = pihole.apiAdguard {
                    if let availability = await adguard.fetchAvailableUpdates() {
                        results.append(ServerUpdates(
                            identifier: pihole.identifier,
                            displayName: pihole.displayName,
                            updates: availability.updates,
                            canSelfUpdate: availability.canSelfUpdate,
                            adguardAPI: adguard
                        ))
                    } else if let previous = self?.latest.first(where: { $0.identifier == pihole.identifier }) {
                        results.append(previous)
                    }
                }
            }
            guard let self else { return }
            self.isChecking = false
            self.latest = results
            NotificationCenter.default.post(name: .piGuardServerUpdatesUpdated, object: nil)
        }
    }

    /// Starts AdGuard Home's self-update on the given server. On success the
    /// server is optimistically marked up to date (it restarts on its own)
    /// and the next poll cycle re-checks.
    func beginSelfUpdate(identifier: String) async -> Bool {
        guard let server = latest.first(where: { $0.identifier == identifier }),
              let api = server.adguardAPI else { return false }
        let success = await api.beginUpdate()
        if success {
            await MainActor.run {
                self.latest = self.latest.map { entry in
                    guard entry.identifier == identifier else { return entry }
                    return ServerUpdates(
                        identifier: entry.identifier,
                        displayName: entry.displayName,
                        updates: [],
                        canSelfUpdate: false,
                        adguardAPI: entry.adguardAPI
                    )
                }
                self.lastCheck = nil
                NotificationCenter.default.post(name: .piGuardServerUpdatesUpdated, object: nil)
            }
        }
        return success
    }
}
