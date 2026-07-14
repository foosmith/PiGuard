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

enum QueryLogStatusFilter: Equatable {
    case all
    case allowed
    case blocked
}

/// Opaque per-server pagination position. Pi-hole v6 pages with a database
/// snapshot cursor plus a row offset; AdGuard Home pages with an
/// older-than-timestamp cursor. A nil cursor means the log is exhausted.
enum QueryLogCursor {
    case pihole6(cursor: Int, start: Int)
    case adguard(olderThan: String)
}

struct QueryLogPage {
    let entries: [QueryLogEntry]
    let nextCursor: QueryLogCursor?
}
