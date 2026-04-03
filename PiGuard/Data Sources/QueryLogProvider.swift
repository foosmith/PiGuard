//
//  QueryLogProvider.swift
//  PiGuard
//

import Foundation

enum QueryLogStatus: String {
    case allowed = "Allowed"
    case blocked = "Blocked"
}

struct QueryLogEntry {
    let timestamp: Date
    let domain: String
    let client: String
    let status: QueryLogStatus
    let serverIdentifier: String
    let serverDisplayName: String
}
