//
//  UpdateAdGuardHomeOperation.swift
//  PiGuard
//
//  Created by Codex on 3/31/26.
//

import Foundation

final class UpdateAdGuardHomeOperation: AsyncOperation, @unchecked Sendable {
    private(set) var pihole: Pihole

    init(_ pihole: Pihole) {
        self.pihole = pihole
    }

    override func main() {
        Log.debug("Updating AdGuard Home: \(pihole.identifier)")
        Task {
            do {
                guard let api = pihole.apiAdguard else {
                    throw APIError.invalidURL
                }

                async let status = api.fetchStatus()
                async let stats = api.fetchStats()
                async let filteringStatus = api.fetchFilteringStatus()

                let statusResult = try await status
                let statsResult = try await stats
                let filteringResult = try await filteringStatus

                let blocked = statsResult.numBlockedFiltering
                let total = statsResult.numDNSQueries
                let percentage = total > 0 ? Double(blocked) / Double(total) * 100.0 : 0.0
                let blocklistSize = filteringResult.filters.filter(\.enabled).reduce(0) { $0 + $1.rulesCount }

                let summary = PiholeAPISummary(
                    domainsBeingBlocked: blocklistSize,
                    dnsQueriesToday: total,
                    adsBlockedToday: blocked,
                    adsPercentageToday: percentage,
                    uniqueDomains: 0,
                    queriesForwarded: 0,
                    queriesCached: 0,
                    uniqueClients: 0,
                    dnsQueriesAllTypes: total,
                    status: statusResult.protectionEnabled ? "enabled" : "disabled"
                )

                self.pihole = Pihole(
                    api: nil,
                    api6: nil,
                    apiAdguard: api,
                    identifier: self.pihole.identifier,
                    online: true,
                    summary: summary,
                    canBeManaged: true,
                    enabled: statusResult.protectionEnabled,
                    backendType: .adguardHome
                )
            } catch {
                Log.error(error)
                self.pihole = Pihole(
                    api: nil,
                    api6: nil,
                    apiAdguard: self.pihole.apiAdguard,
                    identifier: self.pihole.identifier,
                    online: false,
                    summary: nil,
                    canBeManaged: false,
                    enabled: nil,
                    backendType: .adguardHome
                )
            }

            self.state = .isFinished
        }
    }
}
