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
    private var sessionID: String?
    private var sessionExpiry: Date?

    var identifier: String {
        connection.identifier
    }

    private let path: String = "/api"
    private let timeout: Int = 2

    override init() {
        connection = PiholeConnectionV4(
            hostname: "pi.hole",
            port: 80,
            useSSL: false,
            token: "",
            username: "",
            passwordProtected: true,
            adminPanelURL: "http://pi.hole/admin/",
            backendType: .piholeV6
        )
        super.init()
    }

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

    var admin: URL {
        return URL(string: "http://\(connection.hostname):\(connection.port)/admin")!
    }
    
    func checkPassword(password: String, totp: Int?) async throws -> PiholeV6PasswordResponse {
        do {
            return try await post("/auth", responseType: PiholeV6PasswordResponse.self, body: PiholeV6PasswordRequest(password: password, totp: totp))
        } catch URLError.timedOut {
            throw APIError.requestTimedOut
        }
    }
    
    func fetchSummary() async throws -> Pihole6APISummary {
        do {
            return try await get("/stats/summary", responseType: Pihole6APISummary.self, apiKey: try await sessionToken())
        }
    }
    
    func fetchBlockingStatus() async throws -> Pihole6APIBlockingStatus {
        do {
            return try await get("/dns/blocking", responseType: Pihole6APIBlockingStatus.self, apiKey: try await sessionToken())
        }
    }
    
    func disable(seconds: Int?) async throws -> Pihole6APIBlockingStatus {
        do {
            return try await post("/dns/blocking", responseType: Pihole6APIBlockingStatus.self, apiKey: try await sessionToken(), body: PiholeV6BlockingRequest(blocking: false, timer: seconds))
        }
    }
    
    func enable() async throws -> Pihole6APIBlockingStatus {
        do {
            return try await post("/dns/blocking", responseType: Pihole6APIBlockingStatus.self, apiKey: try await sessionToken(), body: PiholeV6BlockingRequest(blocking: true, timer: nil))
        }
    }

    func triggerGravityUpdate() async throws {
        let sid = try await sessionToken()
        let req = request(for: buildURL("/action/gravity", queryItems: nil), method: "POST", apiKey: sid)
        _ = try await performRaw(req)
    }

    // MARK: - Raw HTTP helpers for sync operations

    static func encodePathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func buildURL(_ path: String, queryItems: [URLQueryItem]?) -> URL {
        guard let queryItems, !queryItems.isEmpty,
              var components = URLComponents(string: "\(baseURL)\(path)") else {
            return URL(string: "\(baseURL)\(path)")!
        }
        components.queryItems = queryItems
        return components.url ?? URL(string: "\(baseURL)\(path)")!
    }

    private func performRaw(_ req: URLRequest) async throws -> Data {
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
    }

    func getData(_ path: String, apiKey: String? = nil, queryItems: [URLQueryItem]? = nil) async throws -> Data {
        let sid = try await sessionToken()
        let req = request(for: buildURL(path, queryItems: queryItems), apiKey: sid)
        return try await performRaw(req)
    }

    func postData<B: Encodable>(_ path: String, apiKey: String? = nil, queryItems: [URLQueryItem]? = nil, body: B) async throws -> Data {
        let sid = try await sessionToken()
        let req = request(for: buildURL(path, queryItems: queryItems), method: "POST", apiKey: sid, body: body)
        return try await performRaw(req)
    }

    func putData<B: Encodable>(_ path: String, apiKey: String? = nil, queryItems: [URLQueryItem]? = nil, body: B) async throws -> Data {
        let sid = try await sessionToken()
        let req = request(for: buildURL(path, queryItems: queryItems), method: "PUT", apiKey: sid, body: body)
        return try await performRaw(req)
    }

    func deleteData(_ path: String, apiKey: String? = nil, queryItems: [URLQueryItem]? = nil) async throws -> Data {
        let sid = try await sessionToken()
        let req = request(for: buildURL(path, queryItems: queryItems), method: "DELETE", apiKey: sid)
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

    func fetchQueryLog(limit: Int = 100) async -> [QueryLogEntry] {
        let blockedStatuses: Set<String> = [
            "GRAVITY", "REGEX", "DENYLIST",
            "EXTERNAL_BLOCKED_IP", "EXTERNAL_BLOCKED_NULL", "EXTERNAL_BLOCKED_NXRA",
            "GRAVITY_CNAME", "REGEX_CNAME", "DENYLIST_CNAME", "EXTERNAL_BLOCKED_EDE15"
        ]
        do {
            let data = try await getData("/queries", queryItems: [URLQueryItem(name: "length", value: "\(limit)")])
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let queries = json["queries"] as? [[String: Any]] else { return [] }
            return queries.compactMap { q -> QueryLogEntry? in
                guard let time = q["time"] as? Double,
                      let domain = q["domain"] as? String,
                      let status = q["status"] as? String else { return nil }
                let clientDict = q["client"] as? [String: Any]
                let clientName = (clientDict?["name"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? (clientDict?["ip"] as? String) ?? "unknown"
                return QueryLogEntry(
                    timestamp: Date(timeIntervalSince1970: time),
                    domain: domain,
                    client: clientName,
                    status: blockedStatuses.contains(status) ? .blocked : .allowed,
                    serverIdentifier: identifier,
                    serverDisplayName: connection.endpointDisplayName
                )
            }
        } catch {
            return []
        }
    }

    private struct DomainRuleRequest: Encodable {
        let domain: String
        let comment: String
    }

    func allowDomain(_ domain: String) async -> Bool {
        do {
            _ = try await postData("/domains/allow/exact", body: DomainRuleRequest(domain: domain, comment: "Added via PiGuard"))
            return true
        } catch {
            return false
        }
    }

    func blockDomain(_ domain: String) async -> Bool {
        do {
            _ = try await postData("/domains/deny/exact", body: DomainRuleRequest(domain: domain, comment: "Added via PiGuard"))
            return true
        } catch {
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "sid")
        }
        if let body {
            request.httpBody = try? JSONEncoder().encode(body)
            request.timeoutInterval = 5
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
            throw APIError.requestFailed(error)
        }
    }

    private func get<T: Decodable>(
        _ path: String, responseType: T.Type, apiKey: String? = nil
    ) async throws -> T {
        do {
            let request = request(
                for: URL(string: "\(baseURL)\(path)")!, apiKey: apiKey)
            return try await perform(request, responseType: T.self)
        } catch {
            throw APIError.requestFailed(error)
        }
    }

    private func post<T: Decodable>(
        _ path: String, responseType: T.Type, apiKey: String? = nil,
        body: Encodable? = nil
    ) async throws -> T {
        do {
            let request = request(
                for: URL(string: "\(baseURL)\(path)")!, method: "POST",
                apiKey: apiKey, body: body)
            return try await perform(request, responseType: T.self)
        } catch {
            throw APIError.requestFailed(error)
        }
    }

    private func sessionToken() async throws -> String? {
        if !connection.passwordProtected {
            return nil
        }

        if let sessionID, let sessionExpiry, sessionExpiry > Date() {
            return sessionID
        }

        guard !connection.token.isEmpty else {
            throw APIError.invalidResponse(statusCode: 401, content: "Missing Pi-hole v6 app password")
        }

        let response = try await checkPassword(password: connection.token, totp: nil)

        guard response.session.valid else {
            throw APIError.invalidResponse(
                statusCode: 401,
                content: response.session.message ?? "Invalid Pi-hole v6 app password"
            )
        }

        sessionID = response.session.sid
        if response.session.validity > 0 {
            sessionExpiry = Date().addingTimeInterval(TimeInterval(max(response.session.validity - 5, 0)))
        } else {
            sessionExpiry = nil
        }

        return sessionID
    }

}
