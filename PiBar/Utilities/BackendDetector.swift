//
//  BackendDetector.swift
//  PiBar
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

        async let adguard = fetchJSON(url: "\(prefix)://\(hostname):\(port)/control/status")
        async let piholeV5 = fetchJSON(url: "\(prefix)://\(hostname):\(port)/admin/api.php?summaryRaw")
        async let piholeV6 = fetchJSON(url: "\(prefix)://\(hostname):\(port)/api/auth", method: "POST")

        if let adguardJSON = await adguard,
           adguardJSON["protection_enabled"] != nil {
            return BackendDetectionResult(backendType: .adguardHome, version: adguardJSON["version"] as? String)
        }
        if let piholeV6JSON = await piholeV6,
           let session = piholeV6JSON["session"] as? [String: Any],
           session["sid"] != nil || session["valid"] != nil {
            return BackendDetectionResult(backendType: .piholeV6, version: nil)
        }
        if let piholeV5JSON = await piholeV5,
           piholeV5JSON["dns_queries_today"] != nil {
            return BackendDetectionResult(backendType: .piholeV5, version: nil)
        }
        return nil
    }

    private static func fetchJSON(url: String, method: String = "GET") async -> [String: Any]? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200 ..< 300 ~= http.statusCode else {
                return nil
            }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }
}
