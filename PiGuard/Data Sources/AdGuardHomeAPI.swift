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
        let _: AdGuardHomeStatusResponse = try await request(
            path: "/control/filtering/refresh",
            method: "POST",
            responseType: AdGuardHomeStatusResponse.self
        )
    }

    func testConnection() async throws -> AdGuardHomeStatusResponse {
        try await fetchStatus()
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
