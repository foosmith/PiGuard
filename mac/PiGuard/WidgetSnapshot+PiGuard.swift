//
//  WidgetSnapshot+PiGuard.swift
//  PiGuard
//
//  Convenience initialiser from PiholeNetworkOverview.
//  Main app target only — not included in the PiGuardWidget extension target.

import Foundation

extension WidgetSnapshot {
    init(
        from overview: PiholeNetworkOverview,
        topBlocked: [String] = [],
        topQueries: [String] = []
    ) {
        self.init(
            networkStatus: overview.networkStatus.rawValue,
            totalQueriesToday: overview.totalQueriesToday,
            adsBlockedToday: overview.adsBlockedToday,
            adsPercentageToday: overview.adsPercentageToday,
            averageBlocklist: overview.averageBlocklist,
            updatedAt: Date(),
            serverCount: overview.piholes.count,
            topBlocked: topBlocked,
            topQueries: topQueries
        )
    }
}
