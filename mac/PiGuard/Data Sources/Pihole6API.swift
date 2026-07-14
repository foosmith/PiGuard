//
//  PiholeAPI.swift
//  PiGuard
//
//  Created by Brad Root on 5/17/20.
//  Copyright © 2020 Brad Root. All rights reserved.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Cocoa

struct Pihole6APISummary: Decodable {
    let queries: Queries
    let clients: Clients
    let gravity: Gravity
    let took: Double
}

struct Queries: Decodable {
    let total: Int
    let blocked: Int
    let percentBlocked: Double
    let uniqueDomains: Int
    let forwarded: Int
    let cached: Int
    let frequency: Double
    let types: QueryTypes
    let status: QueryStatus
    let replies: QueryReplies

    enum CodingKeys: String, CodingKey {
        case total, blocked, forwarded, cached, frequency, types, status, replies
        case percentBlocked = "percent_blocked"
        case uniqueDomains = "unique_domains"
    }
}

struct QueryTypes: Decodable {
    let A: Int
    let AAAA: Int
    let ANY: Int
    let SRV: Int
    let SOA: Int
    let PTR: Int
    let TXT: Int
    let NAPTR: Int
    let MX: Int
    let DS: Int
    let RRSIG: Int
    let DNSKEY: Int
    let NS: Int
    let SVCB: Int
    let HTTPS: Int
    let OTHER: Int
}

struct QueryStatus: Decodable {
    let UNKNOWN: Int
    let GRAVITY: Int
    let FORWARDED: Int
    let CACHE: Int
    let REGEX: Int
    let DENYLIST: Int
    let EXTERNAL_BLOCKED_IP: Int
    let EXTERNAL_BLOCKED_NULL: Int
    let EXTERNAL_BLOCKED_NXRA: Int
    let GRAVITY_CNAME: Int
    let REGEX_CNAME: Int
    let DENYLIST_CNAME: Int
    let RETRIED: Int
    let RETRIED_DNSSEC: Int
    let IN_PROGRESS: Int
    let DBBUSY: Int
    let SPECIAL_DOMAIN: Int
    let CACHE_STALE: Int
    let EXTERNAL_BLOCKED_EDE15: Int
}

struct QueryReplies: Decodable {
    let UNKNOWN: Int
    let NODATA: Int
    let NXDOMAIN: Int
    let CNAME: Int
    let IP: Int
    let DOMAIN: Int
    let RRNAME: Int
    let SERVFAIL: Int
    let REFUSED: Int
    let NOTIMP: Int
    let OTHER: Int
    let DNSSEC: Int
    let NONE: Int
    let BLOB: Int
}

struct Clients: Decodable {
    let active: Int
    let total: Int
}

struct Gravity: Decodable {
    let domainsBeingBlocked: Int
    let lastUpdate: Int

    enum CodingKeys: String, CodingKey {
        case domainsBeingBlocked = "domains_being_blocked"
        case lastUpdate = "last_update"
    }
}

enum APIError: Error {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse(statusCode: Int, content: String)
    case decodingFailed
    case requestTimedOut
    case forbidden
    case unauthorized
}

struct PiholeV6Session: Decodable {
    let valid: Bool
    let totp: Bool
    let sid: String?
    let csrf: String?
    let validity: Int
    let message: String?
}

struct PiholeV6PasswordResponse: Decodable {
    let session: PiholeV6Session
    let took: Double
}

struct Pihole6APIEndpoint {
    let path: String
    let authorizationRequired: Bool
}

struct PiholeV6PasswordRequest: Encodable {
    let password: String
    let totp: Int?
}

struct Pihole6APIBlockingStatus: Decodable {
    let blocking: String
    let timer: Double?
    let took: Double
}

struct PiholeV6BlockingRequest: Encodable {
    let blocking: Bool
    let timer: Int?
}

class Pihole6API: NSObject {
    let connection: PiholeConnectionV4
    private let sessionLock = NSLock()
    private var sessionID: String?
    private var sessionExpiry: Date?

    var identifier: String {
        connection.identifier
    }

    private let path: String = "/api"
    private let timeout: TimeInterval = 5

    init(connection: PiholeConnectionV4) {
        self.connection = connection
        super.init()
    }

    // MARK: - URLs

    private var baseURL: String {
        let prefix = connection.useSSL ? "https" : "http"
        return "\(prefix)://\(connection.hostname):\(connection.port)\(path)"
    }

    var userAgent: String = "PiGuard:2.3:https://github.com/foosmith/PiGuard"

    var admin: URL? {
        let prefix = connection.useSSL ? "https" : "http"
        return URL(string: "\(prefix)://\(connection.hostname):\(connection.port)/admin")
    }

    func checkPassword(password: String, totp: Int?) async throws -> PiholeV6PasswordResponse {
        try await post("/auth", responseType: PiholeV6PasswordResponse.self, body: PiholeV6PasswordRequest(password: password, totp: totp))
    }

    func fetchSummary() async throws -> Pihole6APISummary {
        try await get("/stats/summary", responseType: Pihole6APISummary.self, apiKey: try await sessionToken())
    }

    func fetchBlockingStatus() async throws -> Pihole6APIBlockingStatus {
        try await get("/dns/blocking", responseType: Pihole6APIBlockingStatus.self, apiKey: try await sessionToken())
    }

    func disable(seconds: Int?) async throws -> Pihole6APIBlockingStatus {
        try await post("/dns/blocking", responseType: Pihole6APIBlockingStatus.self, apiKey: try await sessionToken(), body: PiholeV6BlockingRequest(blocking: false, timer: seconds))
    }

    func enable() async throws -> Pihole6APIBlockingStatus {
        try await post("/dns/blocking", responseType: Pihole6APIBlockingStatus.self, apiKey: try await sessionToken(), body: PiholeV6BlockingRequest(blocking: true, timer: nil))
    }

    func triggerGravityUpdate() async throws {
        let sid = try await sessionToken()
        let req = request(for: try buildURL("/action/gravity", queryItems: nil), method: "POST", apiKey: sid)
        _ = try await performRaw(req)
    }

    // MARK: - Raw HTTP helpers for sync operations

    static func encodePathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func buildURL(_ path: String, queryItems: [URLQueryItem]?) throws -> URL {
        guard let queryItems, !queryItems.isEmpty,
              var components = URLComponents(string: "\(baseURL)\(path)") else {
            guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
            return url
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private func performRaw(_ req: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                switch http.statusCode {
                case 401: throw APIError.unauthorized
                case 403: throw APIError.forbidden
                default:
                    throw APIError.invalidResponse(
                        statusCode: http.statusCode,
                        content: String(data: data, encoding: .utf8) ?? ""
                    )
                }
            }
            return data
        } catch {
            throw normalizeError(error)
        }
    }

    func getData(_ path: String, queryItems: [URLQueryItem]? = nil) async throws -> Data {
        let sid = try await sessionToken()
        let req = request(for: try buildURL(path, queryItems: queryItems), apiKey: sid)
        return try await performRaw(req)
    }

    func postData<B: Encodable>(_ path: String, queryItems: [URLQueryItem]? = nil, body: B) async throws -> Data {
        let sid = try await sessionToken()
        let req = request(for: try buildURL(path, queryItems: queryItems), method: "POST", apiKey: sid, body: body)
        return try await performRaw(req)
    }

    func putData<B: Encodable>(_ path: String, queryItems: [URLQueryItem]? = nil, body: B) async throws -> Data {
        let sid = try await sessionToken()
        let req = request(for: try buildURL(path, queryItems: queryItems), method: "PUT", apiKey: sid, body: body)
        return try await performRaw(req)
    }

    func deleteData(_ path: String, queryItems: [URLQueryItem]? = nil) async throws -> Data {
        let sid = try await sessionToken()
        let req = request(for: try buildURL(path, queryItems: queryItems), method: "DELETE", apiKey: sid)
        return try await performRaw(req)
    }

    // MARK: - Top Items, Query Log, Allow/Block

    func fetchTopBlocked() async -> [TopItem] {
        do {
            let data = try await getData("/stats/top_domains", queryItems: [URLQueryItem(name: "blocked", value: "true")])
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let domains = json["domains"] as? [[String: Any]] else { return [] }
            return domains.prefix(10).compactMap { dict -> TopItem? in
                guard let domain = dict["domain"] as? String,
                      let count = dict["count"] as? Int else { return nil }
                return TopItem(name: domain, count: count)
            }
        } catch {
            return []
        }
    }

    func fetchTopQueries() async -> [TopItem] {
        do {
            let data = try await getData("/stats/top_domains")
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let domains = json["domains"] as? [[String: Any]] else { return [] }
            return domains.prefix(10).compactMap { dict -> TopItem? in
                guard let domain = dict["domain"] as? String,
                      let count = dict["count"] as? Int else { return nil }
                return TopItem(name: domain, count: count)
            }
        } catch {
            return []
        }
    }

    func fetchTopClients() async -> [TopItem] {
        do {
            let data = try await getData("/stats/top_clients")
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let clients = json["clients"] as? [[String: Any]] else { return [] }
            return clients.prefix(10).compactMap { dict -> TopItem? in
                guard let count = dict["count"] as? Int else { return nil }
                let name = (dict["name"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? (dict["ip"] as? String) ?? "unknown"
                return TopItem(name: name, count: count)
            }
        } catch {
            return []
        }
    }

    private static let blockedQueryStatuses: Set<String> = [
        "GRAVITY", "REGEX", "DENYLIST",
        "EXTERNAL_BLOCKED_IP", "EXTERNAL_BLOCKED_NULL", "EXTERNAL_BLOCKED_NXRA",
        "GRAVITY_CNAME", "REGEX_CNAME", "DENYLIST_CNAME", "EXTERNAL_BLOCKED_EDE15"
    ]

    private func queryLogEntry(from q: [String: Any]) -> QueryLogEntry? {
        guard let time = q["time"] as? Double,
              let domain = q["domain"] as? String,
              let status = q["status"] as? String else { return nil }
        let clientDict = q["client"] as? [String: Any]
        let clientName = (clientDict?["name"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? (clientDict?["ip"] as? String) ?? "unknown"
        return QueryLogEntry(
            timestamp: Date(timeIntervalSince1970: time),
            domain: domain,
            client: clientName,
            status: Self.blockedQueryStatuses.contains(status) ? .blocked : .allowed,
            serverIdentifier: identifier,
            serverDisplayName: connection.endpointDisplayName
        )
    }

    /// Fetches one query log page, filtered server-side.
    ///
    /// FTL's /queries filters domain, client name, and client IP as separate
    /// ANDed parameters, so a "domain or client" search runs one request per
    /// field and merges by row id. All sub-requests share one database
    /// snapshot cursor and row offset, so pages stay stable while paging.
    /// Status filtering is NOT done here — FTL only accepts a single status
    /// value, which cannot express the app's blocked set — the caller narrows.
    func fetchQueryLogPage(searchText: String?, limit: Int = 100, cursor: QueryLogCursor? = nil) async -> QueryLogPage {
        var dbCursor: Int?
        var start = 0
        if case let .pihole6(c, s) = cursor {
            dbCursor = c
            start = s
        }

        let trimmed = searchText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var filterSets: [[URLQueryItem]] = [[]]
        if !trimmed.isEmpty {
            let wildcard = "*\(trimmed)*"
            filterSets = [
                [URLQueryItem(name: "domain", value: wildcard)],
                [URLQueryItem(name: "client_name", value: wildcard)],
            ]
            if trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789.:")) != nil {
                filterSets.append([URLQueryItem(name: "client_ip", value: wildcard)])
            }
        }

        var rowsByID: [Int: [String: Any]] = [:]
        var snapshotCursors: [Int] = []
        var hasMore = false

        for filters in filterSets {
            var items = filters
            items.append(URLQueryItem(name: "length", value: "\(limit)"))
            if start > 0 { items.append(URLQueryItem(name: "start", value: "\(start)")) }
            if let dbCursor { items.append(URLQueryItem(name: "cursor", value: "\(dbCursor)")) }

            guard let data = try? await getData("/queries", queryItems: items),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let queries = json["queries"] as? [[String: Any]] else { continue }

            for q in queries {
                guard let id = q["id"] as? Int else { continue }
                rowsByID[id] = q
            }
            if let responseCursor = json["cursor"] as? Int {
                snapshotCursors.append(responseCursor)
            }
            if let filtered = json["recordsFiltered"] as? Int, start + limit < filtered {
                hasMore = true
            }
        }

        let entries = rowsByID.values
            .compactMap(queryLogEntry)
            .sorted { $0.timestamp > $1.timestamp }

        // The snapshot cursor is fixed on the first page and reused verbatim
        // afterwards; the minimum across sub-requests keeps later pages from
        // including rows a slower sub-request has not seen.
        let nextCursor: QueryLogCursor?
        if hasMore, let snapshot = dbCursor ?? snapshotCursors.min() {
            nextCursor = .pihole6(cursor: snapshot, start: start + limit)
        } else {
            nextCursor = nil
        }
        return QueryLogPage(entries: entries, nextCursor: nextCursor)
    }

    // MARK: - Activity History

    /// One 10-minute bucket from GET /history.
    struct HistoryBucket {
        let timestamp: Date
        let total: Int
        let blocked: Int
    }

    func fetchHistory() async -> [HistoryBucket] {
        do {
            let data = try await getData("/history")
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let history = json["history"] as? [[String: Any]] else { return [] }
            return history.compactMap { bucket -> HistoryBucket? in
                guard let time = bucket["timestamp"] as? Double,
                      let total = bucket["total"] as? Int,
                      let blocked = bucket["blocked"] as? Int else { return nil }
                return HistoryBucket(timestamp: Date(timeIntervalSince1970: time), total: total, blocked: blocked)
            }
        } catch {
            Log.warn("Pi-hole v6 fetchHistory failed on \(identifier): \(error)")
            return []
        }
    }

    // MARK: - Domain Explanation

    /// Asks GET /search/{domain} which rules and gravity lists match a
    /// domain. Allow rules take precedence over deny rules and gravity, so
    /// the verdict follows the same order Pi-hole applies them.
    func explainDomain(_ domain: String) async -> DomainFilterExplanation? {
        let encoded = domain.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? domain
        do {
            let data = try await getData("/search/\(encoded)")
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let search = json["search"] as? [String: Any] else { return nil }

            let domains = search["domains"] as? [[String: Any]] ?? []
            let gravity = search["gravity"] as? [[String: Any]] ?? []

            var details: [String] = []
            var hasEnabledAllow = false
            var hasEnabledDeny = false
            var hasEnabledGravityBlock = false

            for rule in domains {
                guard let text = rule["domain"] as? String,
                      let type = rule["type"] as? String else { continue }
                let kind = rule["kind"] as? String ?? "exact"
                let enabled = rule["enabled"] as? Bool ?? true
                if enabled {
                    if type == "allow" { hasEnabledAllow = true } else { hasEnabledDeny = true }
                }
                let label = type == "allow" ? "Allow" : "Deny"
                details.append("\(label) \(kind) rule: \(text)\(enabled ? "" : " (disabled)")")
            }

            for list in gravity {
                guard let address = list["address"] as? String,
                      let type = list["type"] as? String else { continue }
                let enabled = list["enabled"] as? Bool ?? true
                if enabled && type == "block" { hasEnabledGravityBlock = true }
                let label = type == "block" ? "Blocklist" : "Allowlist"
                details.append("\(label): \(address)\(enabled ? "" : " (disabled)")")
            }

            let verdict: String
            if hasEnabledAllow {
                verdict = "Allowed — an allow rule matches, which overrides deny rules and blocklists"
            } else if hasEnabledDeny {
                verdict = "Blocked by a deny rule"
            } else if hasEnabledGravityBlock {
                verdict = "Blocked by a gravity blocklist"
            } else {
                verdict = "Not blocked — no matching rules or lists"
            }
            return DomainFilterExplanation(verdict: verdict, details: details)
        } catch {
            Log.warn("Pi-hole v6 explainDomain failed on \(identifier): \(error)")
            return nil
        }
    }

    // MARK: - Version Info

    /// Human-readable component updates ("Core v6.0 → v6.1") from
    /// GET /info/version. Empty array = everything up to date; nil = fetch
    /// failed. Components on custom branches report a nil remote version and
    /// are skipped.
    func fetchAvailableUpdates() async -> [String]? {
        do {
            let data = try await getData("/info/version")
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = json["version"] as? [String: Any] else { return nil }
            var updates: [String] = []
            for (label, key) in [("Core", "core"), ("Web", "web"), ("FTL", "ftl")] {
                guard let component = version[key] as? [String: Any],
                      let local = (component["local"] as? [String: Any])?["version"] as? String,
                      let remote = (component["remote"] as? [String: Any])?["version"] as? String,
                      !local.isEmpty, !remote.isEmpty, local != remote else { continue }
                updates.append("\(label) \(local) → \(remote)")
            }
            return updates
        } catch {
            Log.warn("Pi-hole v6 fetchAvailableUpdates failed on \(identifier): \(error)")
            return nil
        }
    }

    // MARK: - Diagnosis Messages

    struct DiagnosisMessage {
        let id: Int
        let timestamp: Date
        let type: String
        let plain: String
    }

    func fetchDiagnosisMessages() async -> [DiagnosisMessage]? {
        do {
            let data = try await getData("/info/messages")
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = json["messages"] as? [[String: Any]] else { return nil }
            return messages.compactMap { message -> DiagnosisMessage? in
                guard let id = message["id"] as? Int,
                      let time = message["timestamp"] as? Double,
                      let plain = message["plain"] as? String else { return nil }
                return DiagnosisMessage(
                    id: id,
                    timestamp: Date(timeIntervalSince1970: time),
                    type: message["type"] as? String ?? "UNKNOWN",
                    plain: plain
                )
            }
        } catch {
            Log.warn("Pi-hole v6 fetchDiagnosisMessages failed on \(identifier): \(error)")
            return nil
        }
    }

    func deleteDiagnosisMessage(id: Int) async -> Bool {
        do {
            _ = try await deleteData("/info/messages/\(id)")
            return true
        } catch {
            Log.warn("Pi-hole v6 deleteDiagnosisMessage(\(id)) failed on \(identifier): \(error)")
            return false
        }
    }

    private struct DomainRuleRequest: Encodable {
        let domain: String
        let comment: String
    }

    func allowDomain(_ domain: String) async -> Bool {
        do {
            _ = try await postData("/domains/allow/exact", body: DomainRuleRequest(domain: domain, comment: "Added via PiGuard"))
            Log.debug("Pi-hole v6 allowDomain succeeded for \(domain) on \(identifier)")
            return true
        } catch {
            Log.warn("Pi-hole v6 allowDomain failed for \(domain) on \(identifier): \(error)")
            return false
        }
    }

    func blockDomain(_ domain: String) async -> Bool {
        do {
            _ = try await postData("/domains/deny/exact", body: DomainRuleRequest(domain: domain, comment: "Added via PiGuard"))
            Log.debug("Pi-hole v6 blockDomain succeeded for \(domain) on \(identifier)")
            return true
        } catch {
            Log.warn("Pi-hole v6 blockDomain failed for \(domain) on \(identifier): \(error)")
            return false
        }
    }

    // Ugly Innards

    private func request(
        for url: URL, method: String = "GET", apiKey: String? = nil,
        body: Encodable? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "sid")
        }
        if let body {
            request.httpBody = try? JSONEncoder().encode(body)
        }
        return request
    }

    private func perform<T: Decodable>(
        _ request: URLRequest, responseType _: T.Type
    ) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(
                for: request)
            if let response = response as? HTTPURLResponse,
                !((200..<300) ~= response.statusCode)
            {
                throw APIError.invalidResponse(
                    statusCode: response.statusCode,
                    content: String(
                        describing: String(data: data, encoding: .utf8)))
            }
            do {
//                Log.debug(String(data: data, encoding: .utf8) ?? "No data")
                let decodedResponse = try JSONDecoder().decode(
                    T.self, from: data)
                return decodedResponse
            } catch {
                throw APIError.decodingFailed
            }
        } catch {
            throw normalizeError(error)
        }
    }

    private func get<T: Decodable>(
        _ path: String, responseType: T.Type, apiKey: String? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        let request = request(for: url, apiKey: apiKey)
        return try await perform(request, responseType: T.self)
    }

    private func post<T: Decodable>(
        _ path: String, responseType: T.Type, apiKey: String? = nil,
        body: Encodable? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        let request = request(for: url, method: "POST", apiKey: apiKey, body: body)
        return try await perform(request, responseType: T.self)
    }

    private func normalizeError(_ error: Error) -> APIError {
        if let apiError = error as? APIError {
            return apiError
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return .requestTimedOut
        }
        return .requestFailed(error)
    }

    private func sessionToken() async throws -> String? {
        if !connection.passwordProtected {
            return nil
        }

        // Fast path: return cached session if still valid (read under lock, no await)
        if let cachedID = cachedSessionToken() {
            return cachedID
        }

        guard !connection.token.isEmpty else {
            throw APIError.invalidResponse(statusCode: 401, content: "Missing Pi-hole v6 app password")
        }

        // Slow path: authenticate outside the lock (await cannot be held under NSLock)
        let response = try await checkPassword(password: connection.token, totp: nil)

        guard response.session.valid else {
            throw APIError.invalidResponse(
                statusCode: 401,
                content: response.session.message ?? "Invalid Pi-hole v6 app password"
            )
        }

        // Write back under lock
        return storeSession(id: response.session.sid, validity: response.session.validity)
    }

    /// Returns the cached session ID if still valid, otherwise nil. Synchronous so
    /// the NSLock is never acquired from an async context — that is unavailable in
    /// Swift 6 (and warns today).
    private func cachedSessionToken() -> String? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if let cachedID = sessionID, let expiry = sessionExpiry, expiry > Date() {
            return cachedID
        }
        return nil
    }

    /// Stores a freshly authenticated session under the lock and returns it.
    private func storeSession(id: String?, validity: Int) -> String? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        sessionID = id
        if validity > 0 {
            sessionExpiry = Date().addingTimeInterval(TimeInterval(max(validity - 5, 0)))
        } else {
            sessionExpiry = nil
        }
        return sessionID
    }

}
