//
//  WidgetSnapshot.swift
//  PiGuard
//
//  Shared between the PiGuard main app target and the PiGuardWidget extension target.
//  Must not import AppKit or Cocoa.

import Foundation

struct WidgetSnapshot: Codable {
    let networkStatus: String   // PiholeNetworkStatus.rawValue
    let totalQueriesToday: Int
    let adsBlockedToday: Int
    let adsPercentageToday: Double
    let averageBlocklist: Int
    let updatedAt: Date
    let serverCount: Int
}

// Convenience initialiser from PiholeNetworkOverview — only available in the
// main app target where AppKit/the full model layer is present.
#if canImport(AppKit)
import AppKit

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
#endif
