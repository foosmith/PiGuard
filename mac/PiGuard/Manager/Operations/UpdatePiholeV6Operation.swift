//
//  UpdatePiholeV6Operation.swift
//  PiGuard
//
//  Created by Brad Root on 3/16/25.
//  Copyright © 2025 Brad Root. All rights reserved.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation

final class UpdatePiholeV6Operation: AsyncOperation, @unchecked Sendable {
    private(set) var pihole: Pihole

    init(_ pihole: Pihole) {
        self.pihole = pihole
    }

    override func main() {
        guard let api6 = pihole.api6 else {
            state = .isFinished
            return
        }
        Log.debug("Updating Pi-hole: \(pihole.identifier)")
        Task {
            var enabled: Bool? = true
            var online = true
            var canBeManaged: Bool = true

            do {
                let result = try await api6.fetchSummary()
                let blockingResult = try await api6.fetchBlockingStatus()

                Log.debug("Blocking result \(blockingResult)")

                if blockingResult.blocking != "enabled" {
                    enabled = false
                }

                let newSummary = PiholeAPISummary(domainsBeingBlocked: result.gravity.domainsBeingBlocked, dnsQueriesToday: result.queries.total, adsBlockedToday: result.queries.blocked, adsPercentageToday: result.queries.percentBlocked, uniqueDomains: result.queries.uniqueDomains, queriesForwarded: result.queries.forwarded, queriesCached: result.queries.cached, uniqueClients: result.clients.active, dnsQueriesAllTypes: 0, status: blockingResult.blocking)

                let updatedPihole: Pihole = Pihole(
                    api: nil,
                    api6: api6,
                    apiAdguard: nil,
                    identifier: self.pihole.identifier,
                    online: online,
                    summary: newSummary,
                    canBeManaged: canBeManaged,
                    enabled: enabled,
                    backendType: .piholeV6
                )
                self.pihole = updatedPihole
            } catch {
                Log.error(error)
                let updatedPihole: Pihole = Pihole(
                    api: nil,
                    api6: api6,
                    apiAdguard: nil,
                    identifier: self.pihole.identifier,
                    online: false,
                    summary: nil,
                    canBeManaged: false,
                    enabled: nil,
                    backendType: .piholeV6
                )
                self.pihole = updatedPihole
            }
            self.state = .isFinished
        }
    }
}
