//
//  AdGuardHomeAPI.swift
//  PiGuard
//
//  Created by Codex on 3/31/26.
//

import Foundation

struct AdGuardHomeStatusResponse: Decodable {
    let protectionEnabled: Bool
    let version: String

    enum CodingKeys: String, CodingKey {
        case protectionEnabled = "protection_enabled"
        case version
    }
}

struct AdGuardHomeStatsResponse: Decodable {
    let numDNSQueries: Int
    let numBlockedFiltering: Int

    enum CodingKeys: String, CodingKey {
        case numDNSQueries = "num_dns_queries"
        case numBlockedFiltering = "num_blocked_filtering"
    }
}

struct AdGuardHomeFilterStatusResponse: Decodable {
    let filters: [AdGuardHomeFilter]
}

struct AdGuardHomeFilter: Decodable {
    let enabled: Bool
    let rulesCount: Int

    enum CodingKeys: String, CodingKey {
        case enabled
        case rulesCount = "rules_count"
    }
}

struct AdGuardHomeProtectionRequest: Encodable {
    let enabled: Bool
    let duration: Int?
}

struct AdGuardHomeFilterRefreshRequest: Encodable {
    let whitelist: Bool
}

struct AdGuardHomeFilterRefreshResponse: Decodable {
    let updated: Int
}

struct AdGuardHomeFullStatsResponse {
    let topQueriedDomains: [TopItem]
    let topBlockedDomains: [TopItem]
    let topClients: [TopItem]
}

final class AdGuardHomeAPI {
    let connection: PiholeConnectionV4

    init(connection: PiholeConnectionV4) {
        self.connection = connection
    }

    var identifier: String { connection.identifier }

    private var baseURL: String {
        let prefix = connection.useSSL ? "https" : "http"
        return "\(prefix)://\(connection.hostname):\(connection.port)"
    }

    private var basicAuthHeader: String {
        let credentials = "\(connection.username):\(connection.token)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    func fetchStatus() async throws -> AdGuardHomeStatusResponse {
        try await request(path: "/control/status", method: "GET", responseType: AdGuardHomeStatusResponse.self)
    }

    func fetchStats() async throws -> AdGuardHomeStatsResponse {
        try await request(path: "/control/stats", method: "GET", responseType: AdGuardHomeStatsResponse.self)
    }

    func fetchFilteringStatus() async throws -> AdGuardHomeFilterStatusResponse {
        try await request(path: "/control/filtering/status", method: "GET", responseType: AdGuardHomeFilterStatusResponse.self)
    }

    @discardableResult
    func setProtection(enabled: Bool, durationMilliseconds: Int? = nil) async throws -> AdGuardHomeStatusResponse {
        try await request(
            path: "/control/protection",
            method: "POST",
            responseType: AdGuardHomeStatusResponse.self,
            body: AdGuardHomeProtectionRequest(enabled: enabled, duration: durationMilliseconds)
        )
    }

    func refreshFilters() async throws {
        let _: AdGuardHomeFilterRefreshResponse = try await request(
            path: "/control/filtering/refresh",
            method: "POST",
            responseType: AdGuardHomeFilterRefreshResponse.self,
            body: AdGuardHomeFilterRefreshRequest(whitelist: false)
        )
    }

    func testConnection() async throws -> AdGuardHomeStatusResponse {
        try await fetchStatus()
    }

    // MARK: - Top Items

    private func parseTopItems(from array: [[String: Int]]) -> [TopItem] {
        array.prefix(10).compactMap { dict in
            guard let (name, count) = dict.first else { return nil }
            return TopItem(name: name, count: count)
        }
    }

    func fetchFullStats() async -> AdGuardHomeFullStatsResponse? {
        guard let url = URL(string: "\(baseURL)/control/stats") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let topQueried = (json["top_queried_domains"] as? [[String: Int]]).map(parseTopItems) ?? []
            let topBlocked = (json["top_blocked_domains"] as? [[String: Int]]).map(parseTopItems) ?? []
            let topClients = (json["top_clients"] as? [[String: Int]]).map(parseTopItems) ?? []
            return AdGuardHomeFullStatsResponse(
                topQueriedDomains: topQueried,
                topBlockedDomains: topBlocked,
                topClients: topClients
            )
        } catch {
            return nil
        }
    }

    func fetchTopQueries() async -> [TopItem] {
        await fetchFullStats()?.topQueriedDomains ?? []
    }

    func fetchTopBlocked() async -> [TopItem] {
        await fetchFullStats()?.topBlockedDomains ?? []
    }

    func fetchTopClients() async -> [TopItem] {
        await fetchFullStats()?.topClients ?? []
    }

    // MARK: - Query Log

    private static let queryLogDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let blockedQueryReasons: Set<String> = [
        "FilteredBlackList", "FilteredBlockedService",
        "FilteredParental", "FilteredSafeBrowsing", "FilteredSafeSearch"
    ]

    /// Fetches one query log page, filtered server-side.
    ///
    /// `search` matches domain or client on the server. A blocked-status
    /// filter is sent as `response_status=filtered`, which is a superset of
    /// the app's blocked set (it includes whitelisted/rewritten rows) — the
    /// caller narrows to the exact set. Pages continue from the `oldest`
    /// timestamp of the previous response.
    func fetchQueryLogPage(searchText: String?, statusFilter: QueryLogStatusFilter, limit: Int = 100, cursor: QueryLogCursor? = nil) async -> QueryLogPage {
        let empty = QueryLogPage(entries: [], nextCursor: nil)
        var components = URLComponents(string: "\(baseURL)/control/querylog")
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        let trimmed = searchText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: trimmed))
        }
        if statusFilter == .blocked {
            queryItems.append(URLQueryItem(name: "response_status", value: "filtered"))
        }
        if case let .adguard(olderThan) = cursor {
            queryItems.append(URLQueryItem(name: "older_than", value: olderThan))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { return empty }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return empty }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json["data"] as? [[String: Any]] else { return empty }

            let parsed = entries.compactMap { entry -> QueryLogEntry? in
                guard let question = entry["question"] as? [String: Any],
                      let domain = question["name"] as? String,
                      let client = entry["client"] as? String,
                      let reason = entry["reason"] as? String,
                      let timeStr = entry["time"] as? String else { return nil }
                let timestamp = Self.queryLogDateFormatter.date(from: timeStr) ?? Date()
                return QueryLogEntry(
                    timestamp: timestamp,
                    domain: domain,
                    client: client,
                    status: Self.blockedQueryReasons.contains(reason) ? .blocked : .allowed,
                    serverIdentifier: identifier,
                    serverDisplayName: connection.endpointDisplayName
                )
            }

            // A short page means the log is exhausted: the server scans until
            // it fills `limit` matches or runs out of entries.
            let oldest = json["oldest"] as? String ?? ""
            let nextCursor: QueryLogCursor? = (entries.count >= limit && !oldest.isEmpty)
                ? .adguard(olderThan: oldest)
                : nil
            return QueryLogPage(entries: parsed, nextCursor: nextCursor)
        } catch {
            return empty
        }
    }

    // MARK: - Domain Explanation

    private func fetchFilterNames() async -> [Int: String] {
        guard let url = URL(string: "\(baseURL)/control/filtering/status") else { return [:] }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            var names: [Int: String] = [:]
            for key in ["filters", "whitelist_filters"] {
                for filter in json[key] as? [[String: Any]] ?? [] {
                    guard let id = filter["id"] as? Int,
                          let name = filter["name"] as? String, !name.isEmpty else { continue }
                    names[id] = name
                }
            }
            return names
        } catch {
            return [:]
        }
    }

    /// Asks GET /control/filtering/check_host how the server would filter a
    /// domain: the reason plus the matching rules, with filter-list ids
    /// resolved to their names (id 0 is the user's custom rules).
    func explainDomain(_ domain: String) async -> DomainFilterExplanation? {
        var components = URLComponents(string: "\(baseURL)/control/filtering/check_host")
        components?.queryItems = [URLQueryItem(name: "name", value: domain)]
        guard let url = components?.url else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reason = json["reason"] as? String else { return nil }

            let verdict: String
            switch reason {
            case "FilteredBlackList":
                verdict = "Blocked by a filter rule"
            case "FilteredBlockedService":
                let service = json["service_name"] as? String ?? "unknown service"
                verdict = "Blocked service: \(service)"
            case "FilteredSafeBrowsing":
                verdict = "Blocked by safe browsing"
            case "FilteredParental":
                verdict = "Blocked by parental control"
            case "FilteredSafeSearch":
                verdict = "Rewritten to enforce safe search"
            case "NotFilteredWhiteList":
                verdict = "Allowed by an allowlist rule"
            case "NotFilteredNotFound":
                verdict = "Not blocked — no matching rules"
            case "Rewritten", "RewrittenAutoHosts", "RewrittenRule":
                verdict = "Rewritten by a DNS rewrite"
            default:
                verdict = reason
            }

            var details: [String] = []
            let rules = json["rules"] as? [[String: Any]] ?? []
            if !rules.isEmpty {
                let filterNames = await fetchFilterNames()
                for rule in rules {
                    guard let text = rule["text"] as? String, !text.isEmpty else { continue }
                    if let listID = rule["filter_list_id"] as? Int {
                        let listName = listID == 0 ? "User rules" : (filterNames[listID] ?? "list #\(listID)")
                        details.append("\(text) — \(listName)")
                    } else {
                        details.append(text)
                    }
                }
            }
            return DomainFilterExplanation(verdict: verdict, details: details)
        } catch {
            Log.warn("AdGuard Home explainDomain failed on \(identifier): \(error)")
            return nil
        }
    }

    // MARK: - Version Info

    struct UpdateAvailability {
        let updates: [String]
        let canSelfUpdate: Bool
    }

    /// Checks POST /control/version.json against the running version from
    /// GET /control/status. `recheck_now: false` lets the server serve its
    /// cached answer (it refreshes on its own every few hours). nil = fetch
    /// failed; empty updates = up to date or update checks disabled.
    func fetchAvailableUpdates() async -> UpdateAvailability? {
        let upToDate = UpdateAvailability(updates: [], canSelfUpdate: false)
        guard let status = try? await fetchStatus() else { return nil }
        guard let url = URL(string: "\(baseURL)/control/version.json") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["recheck_now": false])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            if json["disabled"] as? Bool == true { return upToDate }

            func normalized(_ version: String) -> String {
                version.hasPrefix("v") ? String(version.dropFirst()) : version
            }
            let newVersion = json["new_version"] as? String ?? ""
            guard !newVersion.isEmpty, normalized(newVersion) != normalized(status.version) else {
                return upToDate
            }
            return UpdateAvailability(
                updates: ["AdGuard Home \(status.version) → \(newVersion)"],
                canSelfUpdate: json["can_autoupdate"] as? Bool ?? false
            )
        } catch {
            Log.warn("AdGuard Home fetchAvailableUpdates failed on \(identifier): \(error)")
            return nil
        }
    }

    /// Starts the server's own upgrade procedure (POST /control/update).
    /// The server restarts itself when the update finishes.
    func beginUpdate() async -> Bool {
        guard let url = URL(string: "\(baseURL)/control/update") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                Log.warn("AdGuard Home beginUpdate failed on \(identifier): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return false
            }
            Log.info("AdGuard Home beginUpdate accepted on \(identifier)")
            return true
        } catch {
            Log.warn("AdGuard Home beginUpdate failed on \(identifier): \(error)")
            return false
        }
    }

    // MARK: - Activity History

    /// One hourly bucket derived from GET /control/stats.
    struct HistoryBucket {
        let timestamp: Date
        let total: Int
        let blocked: Int
    }

    /// AdGuard Home reports its activity series as bare per-hour counts with
    /// no timestamps: oldest first, last element covering the current partial
    /// hour. Buckets are only available when the server reports hourly units
    /// (stats retention of 7 days or less); otherwise this returns [].
    func fetchHistory() async -> [HistoryBucket] {
        guard let url = URL(string: "\(baseURL)/control/stats") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return [] }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["time_units"] as? String == "hours",
                  let queries = json["dns_queries"] as? [Int],
                  let blocked = json["blocked_filtering"] as? [Int] else { return [] }

            let count = min(queries.count, blocked.count, 24)
            guard count > 0 else { return [] }
            let currentHourStart = floor(Date().timeIntervalSince1970 / 3600) * 3600
            return zip(queries.suffix(count), blocked.suffix(count)).enumerated().map { index, counts in
                HistoryBucket(
                    timestamp: Date(timeIntervalSince1970: currentHourStart - Double(count - 1 - index) * 3600),
                    total: counts.0,
                    blocked: counts.1
                )
            }
        } catch {
            Log.warn("AdGuard Home fetchHistory failed on \(identifier): \(error)")
            return []
        }
    }

    // MARK: - User Rules

    private func fetchUserRules() async -> [String]? {
        guard let url = URL(string: "\(baseURL)/control/filtering/status") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rules = json["user_rules"] as? [String] else { return nil }
            return rules
        } catch {
            return nil
        }
    }

    private func setUserRules(_ rules: [String]) async -> Bool {
        guard let url = URL(string: "\(baseURL)/control/filtering/set_rules") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["rules": rules])

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return false }
            return true
        } catch {
            return false
        }
    }

    private func blockRule(for domain: String) -> String {
        "||\(domain)^$important"
    }

    private func allowRule(for domain: String) -> String {
        "@@\(blockRule(for: domain))"
    }

    private func normalizedRules(_ rules: [String]) -> [String] {
        var seen = Set<String>()
        return rules.compactMap { rawRule in
            let rule = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rule.isEmpty, seen.insert(rule).inserted else { return nil }
            return rule
        }
    }

    func allowDomain(_ domain: String) async -> Bool {
        guard var rules = await fetchUserRules() else { return false }
        let blockRule = blockRule(for: domain)
        let allowRule = allowRule(for: domain)
        rules.removeAll { $0 == blockRule }
        if !rules.contains(allowRule) { rules.append(allowRule) }
        let updatedRules = normalizedRules(rules)
        let success = await setUserRules(updatedRules)
        if success {
            let persisted = await fetchUserRules() ?? []
            let verified = persisted.contains(allowRule)
            if verified {
                Log.debug("AdGuard Home allowDomain succeeded for \(domain) on \(identifier)")
            } else {
                Log.warn("AdGuard Home allowDomain could not verify persisted rule for \(domain) on \(identifier)")
            }
            return verified
        } else {
            Log.warn("AdGuard Home allowDomain failed for \(domain) on \(identifier)")
        }
        return false
    }

    func blockDomain(_ domain: String) async -> Bool {
        guard var rules = await fetchUserRules() else { return false }
        let blockRule = blockRule(for: domain)
        let allowRule = allowRule(for: domain)
        rules.removeAll { $0 == allowRule }
        if !rules.contains(blockRule) { rules.append(blockRule) }
        let updatedRules = normalizedRules(rules)
        let success = await setUserRules(updatedRules)
        if success {
            let persisted = await fetchUserRules() ?? []
            let verified = persisted.contains(blockRule)
            if verified {
                Log.debug("AdGuard Home blockDomain succeeded for \(domain) on \(identifier)")
            } else {
                Log.warn("AdGuard Home blockDomain could not verify persisted rule for \(domain) on \(identifier)")
            }
            return verified
        } else {
            Log.warn("AdGuard Home blockDomain failed for \(domain) on \(identifier)")
        }
        return false
    }

    private func request<T: Decodable>(
        path: String,
        method: String,
        responseType: T.Type
    ) async throws -> T {
        try await request(path: path, method: method, responseType: responseType, body: Optional<AdGuardHomeProtectionRequest>.none)
    }

    private func request<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        responseType: T.Type,
        body: Body? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(statusCode: -1, content: "Missing HTTP response")
            }
            guard 200 ..< 300 ~= httpResponse.statusCode else {
                let content = String(data: data, encoding: .utf8) ?? ""
                throw APIError.invalidResponse(statusCode: httpResponse.statusCode, content: content)
            }
            do {
                return try JSONDecoder().decode(responseType, from: data)
            } catch {
                throw APIError.decodingFailed
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.requestFailed(error)
        }
    }
}
