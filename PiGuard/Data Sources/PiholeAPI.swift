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

class PiholeAPI: NSObject {
    let connection: PiholeConnectionV4

    var identifier: String {
        connection.identifier
    }

    private let path: String = "/admin/api.php"
    private let timeout: Int = 2

    private enum Endpoints {
        static let summary = PiholeAPIEndpoint(queryParameter: "summaryRaw", authorizationRequired: true)
        static let overTimeData10mins = PiholeAPIEndpoint(queryParameter: "overTimeData10mins", authorizationRequired: true)
        static let topItems = PiholeAPIEndpoint(queryParameter: "topItems", authorizationRequired: true)
        static let topClients = PiholeAPIEndpoint(queryParameter: "topClients", authorizationRequired: true)
        static let enable = PiholeAPIEndpoint(queryParameter: "enable", authorizationRequired: true)
        static let disable = PiholeAPIEndpoint(queryParameter: "disable", authorizationRequired: true)
        static let recentBlocked = PiholeAPIEndpoint(queryParameter: "recentBlocked", authorizationRequired: true)
    }

    override init() {
        connection = PiholeConnectionV4(
            hostname: "pi.hole",
            port: 80,
            useSSL: false,
            token: "",
            username: "",
            passwordProtected: true,
            adminPanelURL: "http://pi.hole/admin/",
            backendType: .piholeV5
        )
        super.init()
    }

    init(connection: PiholeConnectionV4) {
        self.connection = connection
        super.init()
    }

    private func get(_ endpoint: PiholeAPIEndpoint, argument: String? = nil, completion: @escaping (String?) -> Void) {
        var builtURLString = baseURL

        if endpoint.authorizationRequired {
            builtURLString.append(contentsOf: "?auth=\(connection.token)&\(endpoint.queryParameter)")
        } else {
            builtURLString.append(contentsOf: "?\(endpoint.queryParameter)")
        }

        if let argument = argument {
            builtURLString.append(contentsOf: "=\(argument)")
        }

        Log.debug("Built API String: \(builtURLString.replacingOccurrences(of: "auth=\(connection.token)", with: "auth=<REDACTED>"))")

        guard let builtURL = URL(string: builtURLString) else { return completion(nil) }

        var urlRequest = URLRequest(url: builtURL)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = 3
        let session = URLSession(configuration: .default)
        let dataTask = session.dataTask(with: urlRequest) { data, response, error in
            if error != nil {
                return completion(nil)
            }
            if let response = response as? HTTPURLResponse {
                if 200 ..< 300 ~= response.statusCode {
                    if let data = data, let string = String(data: data, encoding: .utf8) {
                        completion(string)
                    } else {
                        completion(nil)
                    }
                } else {
                    completion(nil)
                }
            } else {
                completion(nil)
            }
        }
        dataTask.resume()
    }

    private func decodeJSON<T>(_ string: String) -> T? where T: Decodable {
        do {
            let jsonDecoder = JSONDecoder()
            jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let jsonData = string.data(using: .utf8) else { return nil }
            let object = try jsonDecoder.decode(T.self, from: jsonData)
            return object
        } catch {
            return nil
        }
    }

    private func getAsync(_ endpoint: PiholeAPIEndpoint, argument: String? = nil) async -> String? {
        await withCheckedContinuation { continuation in
            get(endpoint, argument: argument) { result in
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - URLs

    private var baseURL: String {
        let prefix = connection.useSSL ? "https" : "http"
        return "\(prefix)://\(connection.hostname):\(connection.port)\(path)"
    }

    var admin: URL {
        let prefix = connection.useSSL ? "https" : "http"
        return URL(string: "\(prefix)://\(connection.hostname):\(connection.port)/admin")!
    }

    // MARK: - Testing

    func testConnection(completion: @escaping (PiholeConnectionTestResult) -> Void) {
        fetchTopItems { string in
            DispatchQueue.main.async {
                if let contents = string {
                    if contents == "[]" {
                        completion(.failureInvalidToken)
                    } else {
                        completion(.success)
                    }
                } else {
                    completion(.failure)
                }
            }
        }
    }

    // MARK: - Endpoints

    func fetchSummary(completion: @escaping (PiholeAPISummary?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            self.get(Endpoints.summary) { string in
                guard let jsonString = string,
                    let summary: PiholeAPISummary = self.decodeJSON(jsonString) else { return completion(nil) }
                completion(summary)
            }
        }
    }

    func fetchTopItems(completion: @escaping (String?) -> Void) {
        // Only using this endpoint to verify the API token
        // So we don't actually do anything with the output yet
        DispatchQueue.global(qos: .background).async {
            self.get(Endpoints.topItems) { string in
                completion(string)
            }
        }
    }

    func fetchTopBlocked() async -> [TopItem] {
        guard let string = await getAsync(Endpoints.topItems) else { return [] }
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let topAds = json["top_ads"] as? [String: Int] else { return [] }
        return topAds.map { TopItem(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(10)
            .map { $0 }
    }

    func fetchTopClients() async -> [TopItem] {
        guard let string = await getAsync(Endpoints.topClients) else { return [] }
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let topSources = json["top_sources"] as? [String: Int] else { return [] }
        return topSources.map { TopItem(name: $0.key.components(separatedBy: "|").first ?? $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(10)
            .map { $0 }
    }

    func fetchQueryLog(limit: Int = 100) async -> [QueryLogEntry] {
        let endpoint = PiholeAPIEndpoint(queryParameter: "getAllQueries=\(limit)", authorizationRequired: true)
        guard let string = await getAsync(endpoint) else { return [] }
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["data"] as? [[Any]] else { return [] }

        let blockedCodes: Set<Int> = [1, 4, 5, 6, 7, 8, 9, 10, 11]
        return rows.compactMap { row -> QueryLogEntry? in
            guard row.count >= 5,
                  let timestampStr = row[0] as? String,
                  let timestampInt = Int(timestampStr),
                  let domain = row[2] as? String,
                  let client = row[3] as? String,
                  let statusCode = (row[4] as? Int) ?? Int(row[4] as? String ?? "") else { return nil }
            let status: QueryLogStatus = blockedCodes.contains(statusCode) ? .blocked : .allowed
            return QueryLogEntry(
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestampInt)),
                domain: domain,
                client: client,
                status: status,
                serverIdentifier: identifier,
                serverDisplayName: connection.endpointDisplayName
            )
        }
    }

    func allowDomain(_ domain: String) async -> Bool {
        guard let encoded = domain.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return false }
        let endpoint = PiholeAPIEndpoint(queryParameter: "list=white&add=\(encoded)", authorizationRequired: true)
        let result = await getAsync(endpoint)
        return result != nil
    }

    func blockDomain(_ domain: String) async -> Bool {
        guard let encoded = domain.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return false }
        let endpoint = PiholeAPIEndpoint(queryParameter: "list=black&add=\(encoded)", authorizationRequired: true)
        let result = await getAsync(endpoint)
        return result != nil
    }

    func disable(seconds: Int? = nil, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .background).async {
            var secondsString: String?
            if let seconds = seconds {
                secondsString = String(seconds)
            }
            self.get(Endpoints.disable, argument: secondsString) { string in
                guard let jsonString = string,
                    let _: PiholeAPIStatus = self.decodeJSON(jsonString) else { return completion(false) }
                completion(true)
            }
        }
    }

    func enable(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .background).async {
            self.get(Endpoints.enable) { string in
                guard let jsonString = string,
                    let _: PiholeAPIStatus = self.decodeJSON(jsonString) else { return completion(false) }
                completion(true)
            }
        }
    }
}
