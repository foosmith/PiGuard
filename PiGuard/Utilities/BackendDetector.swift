//
//  BackendDetector.swift
//  PiGuard
//
//  Created by Codex on 3/31/26.
//

import Foundation

struct BackendDetectionResult {
    let backendType: BackendType
    let version: String?

    var displayString: String {
        if let version, !version.isEmpty {
            return "Detected: \(backendType.displayName) \(version)"
        }
        return "Detected: \(backendType.displayName)"
    }
}

enum BackendDetector {
    static func detect(hostname: String, port: Int, useSSL: Bool) async -> BackendDetectionResult? {
        let prefix = useSSL ? "https" : "http"

        async let adguard = fetchProbe(url: "\(prefix)://\(hostname):\(port)/control/status")
        async let piholeV5 = fetchProbe(url: "\(prefix)://\(hostname):\(port)/admin/api.php?summaryRaw")
        async let piholeV6 = fetchProbe(url: "\(prefix)://\(hostname):\(port)/api/auth", method: "POST")

        if let adguardResult = await adguard,
           let adguardJSON = adguardResult.json,
           adguardJSON["protection_enabled"] != nil {
            return BackendDetectionResult(backendType: .adguardHome, version: adguardJSON["version"] as? String)
        }
        if let adguardResult = await adguard,
           adguardResult.statusCode == 401,
           adguardResult.wwwAuthenticate?.localizedCaseInsensitiveContains("basic") == true {
            return BackendDetectionResult(backendType: .adguardHome, version: nil)
        }
        if let piholeV6Result = await piholeV6,
           let piholeV6JSON = piholeV6Result.json,
           let session = piholeV6JSON["session"] as? [String: Any],
           session["sid"] != nil || session["valid"] != nil || session["message"] != nil {
            return BackendDetectionResult(backendType: .piholeV6, version: nil)
        }
        if let piholeV5Result = await piholeV5,
           let piholeV5JSON = piholeV5Result.json,
           piholeV5JSON["dns_queries_today"] != nil {
            return BackendDetectionResult(backendType: .piholeV5, version: nil)
        }
        return nil
    }

    private static func fetchProbe(url: String, method: String = "GET") async -> BackendProbeResult? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return nil
            }

            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return BackendProbeResult(
                statusCode: http.statusCode,
                json: json,
                wwwAuthenticate: http.value(forHTTPHeaderField: "WWW-Authenticate")
            )
        } catch {
            return nil
        }
    }
}

private struct BackendProbeResult {
    let statusCode: Int
    let json: [String: Any]?
    let wwwAuthenticate: String?
}
