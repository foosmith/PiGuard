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

