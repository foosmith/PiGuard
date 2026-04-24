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
    let topBlocked: [String]
    let topQueries: [String]

    init(
        networkStatus: String,
        totalQueriesToday: Int,
        adsBlockedToday: Int,
        adsPercentageToday: Double,
        averageBlocklist: Int,
        updatedAt: Date,
        serverCount: Int,
        topBlocked: [String] = [],
        topQueries: [String] = []
    ) {
        self.networkStatus = networkStatus
        self.totalQueriesToday = totalQueriesToday
        self.adsBlockedToday = adsBlockedToday
        self.adsPercentageToday = adsPercentageToday
        self.averageBlocklist = averageBlocklist
        self.updatedAt = updatedAt
        self.serverCount = serverCount
        self.topBlocked = topBlocked
        self.topQueries = topQueries
    }

    enum CodingKeys: String, CodingKey {
        case networkStatus
        case totalQueriesToday
        case adsBlockedToday
        case adsPercentageToday
        case averageBlocklist
        case updatedAt
        case serverCount
        case topBlocked
        case topQueries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        networkStatus = try container.decode(String.self, forKey: .networkStatus)
        totalQueriesToday = try container.decode(Int.self, forKey: .totalQueriesToday)
        adsBlockedToday = try container.decode(Int.self, forKey: .adsBlockedToday)
        adsPercentageToday = try container.decode(Double.self, forKey: .adsPercentageToday)
        averageBlocklist = try container.decode(Int.self, forKey: .averageBlocklist)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        serverCount = try container.decode(Int.self, forKey: .serverCount)
        topBlocked = try container.decodeIfPresent([String].self, forKey: .topBlocked) ?? []
        topQueries = try container.decodeIfPresent([String].self, forKey: .topQueries) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(networkStatus, forKey: .networkStatus)
        try container.encode(totalQueriesToday, forKey: .totalQueriesToday)
        try container.encode(adsBlockedToday, forKey: .adsBlockedToday)
        try container.encode(adsPercentageToday, forKey: .adsPercentageToday)
        try container.encode(averageBlocklist, forKey: .averageBlocklist)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(serverCount, forKey: .serverCount)
        try container.encode(topBlocked, forKey: .topBlocked)
        try container.encode(topQueries, forKey: .topQueries)
    }
}
