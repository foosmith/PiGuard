//
//  WidgetSnapshot+PiGuard.swift
//  PiGuard
//
//  Convenience initialiser from PiholeNetworkOverview.
//  Main app target only — not included in the PiGuardWidget extension target.

import Foundation

extension WidgetSnapshot {
    init(from overview: PiholeNetworkOverview) {
        self.networkStatus = overview.networkStatus.rawValue
        self.totalQueriesToday = overview.totalQueriesToday
        self.adsBlockedToday = overview.adsBlockedToday
        self.adsPercentageToday = overview.adsPercentageToday
        self.averageBlocklist = overview.averageBlocklist
        self.updatedAt = Date()
        self.serverCount = overview.piholes.count
    }
}
