# Cross-Platform Stats & Query Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add top blocked domains, top clients submenus, a query log window, and quick allow/block actions across Pi-hole v5, v6, and AdGuard Home.

**Architecture:** Each API class gets new fetch methods returning shared model types (`TopItem`, `QueryLogEntry`). Menu submenus are built on-demand when the menu opens. The query log lives in a standalone `NSWindow` with a table view and server filter. Allow/block pushes to all applicable servers based on sync settings.

**Tech Stack:** Swift, AppKit (NSMenu, NSTableView, NSWindow), async/await with `withCheckedContinuation` bridge for v5.

**Spec:** `docs/superpowers/specs/2026-04-03-cross-platform-stats-querylog-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `PiGuard/Data Sources/TopItemsProvider.swift` | Shared `TopItem` model + fetch methods that dispatch to the correct API per server |
| `PiGuard/Data Sources/QueryLogProvider.swift` | Shared `QueryLogEntry` model + fetch/allow/block methods that dispatch per server |
| `PiGuard/Views/QueryLog/QueryLogWindowController.swift` | Window setup, lazy singleton access |
| `PiGuard/Views/QueryLog/QueryLogViewController.swift` | Table view, server filter, refresh, context menu for allow/block |

### Modified Files

| File | Changes |
|------|---------|
| `PiGuard/Data Sources/PiholeAPI.swift` | Add async wrappers; `fetchTopBlocked()`, `fetchTopClients()`, `fetchQueryLog()`, `allowDomain()`, `blockDomain()` |
| `PiGuard/Data Sources/Pihole6API.swift` | Add `fetchTopBlocked()`, `fetchTopClients()`, `fetchQueryLog()`, `allowDomain()`, `blockDomain()` |
| `PiGuard/Data Sources/AdGuardHomeAPI.swift` | Add `fetchTopBlocked()`, `fetchTopClients()`, `fetchQueryLog()`, `allowDomain()`, `blockDomain()` |
| `PiGuard/Views/Main Menu/MainMenuController.swift` | Add Top Blocked, Top Clients, Query Log menu items; `menuWillOpen`; update `clearSubmenus()` |
| `PiGuard/Views/Main Menu/MainMenu.xib` | Add new menu items between Blocklist and separator |
| `PiGuard.xcodeproj/project.pbxproj` | Register new Swift files |

---

## Task 1: Shared Data Models

**Files:**
- Create: `PiGuard/Data Sources/TopItemsProvider.swift`
- Create: `PiGuard/Data Sources/QueryLogProvider.swift`

- [ ] **Step 1: Create TopItemsProvider.swift with TopItem model**

```swift
//
//  TopItemsProvider.swift
//  PiGuard
//

import Foundation

struct TopItem {
    let name: String
    let count: Int
}
```

- [ ] **Step 2: Create QueryLogProvider.swift with QueryLogEntry model**

```swift
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
```

- [ ] **Step 3: Add files to Xcode project**

Add both new files to `project.pbxproj`. For each file, you need to add:
1. A `PBXFileReference` entry in the file references section (generate a unique 24-char hex UUID, e.g., `FBAA0020FBAA0020FBAA0020`)
2. A `PBXBuildFile` entry in the build files section referencing the file ref
3. The file reference UUID in the "Data Sources" `PBXGroup` children list (where `AdGuardHomeAPI.swift` etc. are listed)
4. The build file UUID in the `PBXSourcesBuildPhase` sources list

Follow the exact pattern of existing entries like `AdGuardHomeAPI.swift` (`FBAA0010FBAA0010FBAA0010`). Note: `Structs.swift` does NOT need changes — the models live in the new files.

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project PiGuard.xcodeproj -scheme PiGuard build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add PiGuard/Data\ Sources/TopItemsProvider.swift PiGuard/Data\ Sources/QueryLogProvider.swift PiGuard.xcodeproj/project.pbxproj
git commit -m "feat: add TopItem and QueryLogEntry shared data models"
```

---

## Task 2: Pi-hole v5 API — Top Items + Query Log + Allow/Block

**Files:**
- Modify: `PiGuard/Data Sources/PiholeAPI.swift`

Pi-hole v5 uses completion handlers. Each new method wraps the existing `get()` in `withCheckedContinuation` to provide an async interface.

- [ ] **Step 1: Add async helper to PiholeAPI**

Add this private method after the existing `decodeJSON` method (after line 105):

```swift
private func getAsync(_ endpoint: PiholeAPIEndpoint, argument: String? = nil) async -> String? {
    await withCheckedContinuation { continuation in
        get(endpoint, argument: argument) { result in
            continuation.resume(returning: result)
        }
    }
}
```

- [ ] **Step 2: Add fetchTopBlocked()**

The `topItems` endpoint returns `{ "top_ads": { "domain": count, ... }, "top_queries": { ... } }`. Add after the existing `fetchTopItems` method:

```swift
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
```

- [ ] **Step 3: Add fetchTopClients()**

The `topClients` endpoint returns `{ "top_sources": { "client|hostname": count, ... } }`. The key may contain `|hostname` suffix — strip it for display.

```swift
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
```

- [ ] **Step 4: Add fetchQueryLog()**

The `getAllQueries` endpoint returns `{ "data": [[fields...], ...] }`. Array indices: 0=timestamp, 1=type, 2=domain, 3=client, 4=status_code. Blocked status codes: 1,4,5,6,7,8,9,10,11.

```swift
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
```

- [ ] **Step 5: Add allowDomain() and blockDomain()**

```swift
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
```

- [ ] **Step 6: Build to verify**

Run: `xcodebuild -project PiGuard.xcodeproj -scheme PiGuard build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add PiGuard/Data\ Sources/PiholeAPI.swift
git commit -m "feat: add top items, query log, and allow/block to Pi-hole v5 API"
```

---

## Task 3: Pi-hole v6 API — Top Items + Query Log + Allow/Block

**Files:**
- Modify: `PiGuard/Data Sources/Pihole6API.swift`

v6 already uses async/await. Add methods using the existing `getData`/`postData` helpers.

- [ ] **Step 1: Add fetchTopBlocked()**

The v6 endpoint `GET /api/stats/top_domains?blocked=true` returns `{ "domains": [{ "domain": "...", "count": N }], ... }`.

```swift
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
```

- [ ] **Step 2: Add fetchTopClients()**

`GET /api/stats/top_clients` returns `{ "clients": [{ "name": "...", "ip": "...", "count": N }], ... }`. Prefer `name` over `ip`.

```swift
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
```

- [ ] **Step 3: Add fetchQueryLog()**

`GET /api/queries?length=100` returns `{ "queries": [{ "id": N, "time": epoch, "type": "...", "domain": "...", "client": { "ip": "...", "name": "..." }, "status": "FORWARDED|GRAVITY|..." }] }`.

Blocked statuses: GRAVITY, REGEX, DENYLIST, EXTERNAL_BLOCKED_IP, EXTERNAL_BLOCKED_NULL, EXTERNAL_BLOCKED_NXRA, GRAVITY_CNAME, REGEX_CNAME, DENYLIST_CNAME, EXTERNAL_BLOCKED_EDE15.

```swift
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
```

- [ ] **Step 4: Add allowDomain() and blockDomain()**

`POST /api/domains/allow/exact` with body `{ "domain": "...", "comment": "Added via PiGuard" }`.

Add this private struct inside the `Pihole6API` class body (not at file scope):

```swift
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
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild -project PiGuard.xcodeproj -scheme PiGuard build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add PiGuard/Data\ Sources/Pihole6API.swift
git commit -m "feat: add top items, query log, and allow/block to Pi-hole v6 API"
```

---

## Task 4: AdGuard Home API — Top Items + Query Log + Allow/Block

**Files:**
- Modify: `PiGuard/Data Sources/AdGuardHomeAPI.swift`

AdGuard already uses async/await. The stats endpoint returns top blocked and top clients in single-key dictionary arrays. Allow/block uses read-modify-write on custom filtering rules.

- [ ] **Step 1: Add helper to parse AdGuard single-key dict arrays**

AdGuard returns `[{"domain.com": 1234}, {"other.com": 567}]` — each element is a dict with one key.

Add as a private method in `AdGuardHomeAPI`:

```swift
private func parseTopItems(from array: [[String: Int]]) -> [TopItem] {
    array.prefix(10).compactMap { dict in
        guard let (name, count) = dict.first else { return nil }
        return TopItem(name: name, count: count)
    }
}
```

- [ ] **Step 2: Add response model for full stats**

The `/control/stats` endpoint returns more fields than the current `AdGuardHomeStatsResponse` captures. Rather than modifying the existing struct (which is used by the polling operation), add a new response type for the extended stats:

```swift
struct AdGuardHomeFullStatsResponse {
    let topBlockedDomains: [TopItem]
    let topClients: [TopItem]
}
```

- [ ] **Step 3: Add fetchTopBlocked() and fetchTopClients()**

Both come from the same `/control/stats` endpoint. Fetch once, parse both.

```swift
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

        let topBlocked = (json["top_blocked_domains"] as? [[String: Int]]).map(parseTopItems) ?? []
        let topClients = (json["top_clients"] as? [[String: Int]]).map(parseTopItems) ?? []
        return AdGuardHomeFullStatsResponse(topBlockedDomains: topBlocked, topClients: topClients)
    } catch {
        return nil
    }
}

func fetchTopBlocked() async -> [TopItem] {
    await fetchFullStats()?.topBlockedDomains ?? []
}

func fetchTopClients() async -> [TopItem] {
    await fetchFullStats()?.topClients ?? []
}
```

Note: `fetchTopBlocked` and `fetchTopClients` are convenience wrappers. When both are needed (e.g., in `menuWillOpen`), the caller should call `fetchFullStats()` directly to avoid a double HTTP request — see Task 5 Step 3.

- [ ] **Step 4: Add fetchQueryLog()**

`GET /control/querylog?limit=100` returns:
```json
{ "data": [{ "answer": [...], "time": "2024-01-01T00:00:00Z", "QH": "domain.com", "QT": "A", "IP": "192.168.1.1", "reason": "FilteredBlackList", ... }] }
```

Blocked reasons: FilteredBlackList, FilteredBlockedService, FilteredParental, FilteredSafeBrowsing, FilteredSafeSearch.

```swift
func fetchQueryLog(limit: Int = 100) async -> [QueryLogEntry] {
    let blockedReasons: Set<String> = [
        "FilteredBlackList", "FilteredBlockedService",
        "FilteredParental", "FilteredSafeBrowsing", "FilteredSafeSearch"
    ]

    guard let url = URL(string: "\(baseURL)/control/querylog?limit=\(limit)") else { return [] }
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.timeoutInterval = 5
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")

    do {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else { return [] }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return entries.compactMap { entry -> QueryLogEntry? in
            guard let domain = entry["QH"] as? String,
                  let client = entry["IP"] as? String,
                  let reason = entry["reason"] as? String,
                  let timeStr = entry["time"] as? String else { return nil }
            let timestamp = formatter.date(from: timeStr) ?? Date()
            return QueryLogEntry(
                timestamp: timestamp,
                domain: domain,
                client: client,
                status: blockedReasons.contains(reason) ? .blocked : .allowed,
                serverIdentifier: identifier,
                serverDisplayName: connection.endpointDisplayName
            )
        }
    } catch {
        return []
    }
}
```

- [ ] **Step 5: Add allowDomain() and blockDomain()**

Read-modify-write on custom filtering rules. `GET /control/filtering/status` returns `{ "user_rules": ["rule1", "rule2", ...], ... }`. `POST /control/filtering/set_rules` accepts `{ "rules": ["rule1", "rule2", ...] }`.

```swift
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
    // AdGuard Home expects rules as a single newline-joined string, not an array
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["rules": rules.joined(separator: "\n")])

    do {
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return false }
        return true
    } catch {
        return false
    }
}

func allowDomain(_ domain: String) async -> Bool {
    guard var rules = await fetchUserRules() else { return false }
    let rule = "@@||\(domain)^"
    if !rules.contains(rule) { rules.append(rule) }
    return await setUserRules(rules)
}

func blockDomain(_ domain: String) async -> Bool {
    guard var rules = await fetchUserRules() else { return false }
    let rule = "||\(domain)^"
    if !rules.contains(rule) { rules.append(rule) }
    return await setUserRules(rules)
}
```

- [ ] **Step 6: Make baseURL and basicAuthHeader internal for reuse**

The `baseURL` and `basicAuthHeader` properties are currently `private`. The new methods need direct URL access since they use `URLSession` directly (to avoid needing new `Decodable` response types for JSON structures that vary). Change their access level from `private` to `fileprivate` or make them `internal` — or keep them private and add the new methods inside the class body (which they already are). No change needed if the methods are added inside the class.

- [ ] **Step 7: Build to verify**

Run: `xcodebuild -project PiGuard.xcodeproj -scheme PiGuard build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add PiGuard/Data\ Sources/AdGuardHomeAPI.swift
git commit -m "feat: add top items, query log, and allow/block to AdGuard Home API"
```

---

## Task 5: Menu Items — Top Blocked and Top Clients Submenus

**Files:**
- Modify: `PiGuard/Views/Main Menu/MainMenu.xib`
- Modify: `PiGuard/Views/Main Menu/MainMenuController.swift`

- [ ] **Step 1: Add new menu items to MainMenu.xib**

In `MainMenu.xib`, add three new menu items after the "Blocklist: 0" item (after `id="6lr-WP-jec"`) and before the separator (`id="gzf-LJ-6hp"`):

```xml
<menuItem title="Top Blocked" id="FBM-TB-001">
    <modifierMask key="keyEquivalentModifierMask"/>
    <menu key="submenu" title="Top Blocked" id="FBM-TB-MNU">
        <items>
            <menuItem title="Loading..." enabled="NO" id="FBM-TB-LDG">
                <modifierMask key="keyEquivalentModifierMask"/>
            </menuItem>
        </items>
    </menu>
</menuItem>
<menuItem title="Top Clients" id="FBM-TC-001">
    <modifierMask key="keyEquivalentModifierMask"/>
    <menu key="submenu" title="Top Clients" id="FBM-TC-MNU">
        <items>
            <menuItem title="Loading..." enabled="NO" id="FBM-TC-LDG">
                <modifierMask key="keyEquivalentModifierMask"/>
            </menuItem>
        </items>
    </menu>
</menuItem>
<menuItem isSeparatorItem="YES" id="FBM-SP-001"/>
<menuItem title="Query Log..." id="FBM-QL-001">
    <modifierMask key="keyEquivalentModifierMask"/>
</menuItem>
<menuItem isSeparatorItem="YES" id="FBM-SP-002"/>
```

Also add outlet connections from the `MainMenuController` object (`id="Ufk-kp-3MV"`):

```xml
<outlet property="topBlockedMenuItem" destination="FBM-TB-001" id="FBM-TB-OUT"/>
<outlet property="topClientsMenuItem" destination="FBM-TC-001" id="FBM-TC-OUT"/>
<outlet property="queryLogMenuItem" destination="FBM-QL-001" id="FBM-QL-OUT"/>
```

And add an action connection for the Query Log menu item:

```xml
<connections>
    <action selector="queryLogAction:" target="Ufk-kp-3MV" id="FBM-QL-ACT"/>
</connections>
```

- [ ] **Step 2: Add outlets and properties to MainMenuController.swift**

After the existing outlet declarations (around line 74), add:

```swift
@IBOutlet var topBlockedMenuItem: NSMenuItem!
@IBOutlet var topClientsMenuItem: NSMenuItem!
@IBOutlet var queryLogMenuItem: NSMenuItem!
```

Add instance variables for on-demand fetch state (after the existing `menuBarActivityFrame` around line 30):

```swift
private var isFetchingTopItems = false
private var cachedTopBlocked: [String: [TopItem]] = [:]
private var cachedTopClients: [String: [TopItem]] = [:]
```

- [ ] **Step 3: Add menuWillOpen delegate to fetch top items on demand**

`MainMenuController` already conforms to `NSMenuDelegate`. The `mainMenu`'s delegate is set to the AppDelegate in the XIB (`XG5-ia-nhZ`). We need to handle menu open events. The status bar item's menu delegate should be `self`. In `awakeFromNib()`, after `mainMenu.delegate = self` (line 145), the menu delegate is already set.

However, looking at the XIB, the menu delegate is set to the AppDelegate (`FU8-KO-8vo`), not `MainMenuController`. The `mainMenu.delegate = self` line at 145 overrides this at runtime — so `menuWillOpen` on `MainMenuController` will work.

Add this method:

```swift
func menuWillOpen(_ menu: NSMenu) {
    guard menu == mainMenu, !isFetchingTopItems else { return }
    isFetchingTopItems = true

    guard let networkOverview = networkOverview else {
        isFetchingTopItems = false
        return
    }

    Task {
        var allTopBlocked: [String: [TopItem]] = [:]
        var allTopClients: [String: [TopItem]] = [:]

        for pihole in networkOverview.piholes.values {
            if let api = pihole.api {
                allTopBlocked[pihole.identifier] = await api.fetchTopBlocked()
                allTopClients[pihole.identifier] = await api.fetchTopClients()
            } else if let api6 = pihole.api6 {
                allTopBlocked[pihole.identifier] = await api6.fetchTopBlocked()
                allTopClients[pihole.identifier] = await api6.fetchTopClients()
            } else if let apiAdguard = pihole.apiAdguard {
                // Single fetch for both — avoids duplicate HTTP request
                if let stats = await apiAdguard.fetchFullStats() {
                    allTopBlocked[pihole.identifier] = stats.topBlockedDomains
                    allTopClients[pihole.identifier] = stats.topClients
                }
            }
        }

        await MainActor.run {
            self.cachedTopBlocked = allTopBlocked
            self.cachedTopClients = allTopClients
            self.rebuildTopBlockedSubmenu()
            self.rebuildTopClientsSubmenu()
            self.isFetchingTopItems = false
        }
    }
}
```

- [ ] **Step 4: Add submenu rebuild methods**

```swift
private func rebuildTopBlockedSubmenu() {
    guard let submenu = topBlockedMenuItem.submenu else { return }
    submenu.removeAllItems()

    guard let networkOverview = networkOverview else {
        submenu.addItem(NSMenuItem(title: "Unavailable", action: nil, keyEquivalent: ""))
        return
    }

    let sortedPiholes = networkOverview.piholes.values.sorted {
        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
    let showServerNames = sortedPiholes.count > 1

    for (index, pihole) in sortedPiholes.enumerated() {
        if showServerNames {
            if index > 0 { submenu.addItem(NSMenuItem.separator()) }
            let header = NSMenuItem(title: pihole.displayName, action: nil, keyEquivalent: "")
            header.isEnabled = false
            submenu.addItem(header)
        }

        let items = cachedTopBlocked[pihole.identifier] ?? []
        if items.isEmpty {
            let empty = NSMenuItem(title: "No data", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for item in items {
                let menuItem = NSMenuItem(title: "\(item.name)  (\(item.count.string))", action: nil, keyEquivalent: "")
                menuItem.isEnabled = false
                submenu.addItem(menuItem)
            }
        }
    }
}

private func rebuildTopClientsSubmenu() {
    guard let submenu = topClientsMenuItem.submenu else { return }
    submenu.removeAllItems()

    guard let networkOverview = networkOverview else {
        submenu.addItem(NSMenuItem(title: "Unavailable", action: nil, keyEquivalent: ""))
        return
    }

    let sortedPiholes = networkOverview.piholes.values.sorted {
        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
    let showServerNames = sortedPiholes.count > 1

    for (index, pihole) in sortedPiholes.enumerated() {
        if showServerNames {
            if index > 0 { submenu.addItem(NSMenuItem.separator()) }
            let header = NSMenuItem(title: pihole.displayName, action: nil, keyEquivalent: "")
            header.isEnabled = false
            submenu.addItem(header)
        }

        let items = cachedTopClients[pihole.identifier] ?? []
        if items.isEmpty {
            let empty = NSMenuItem(title: "No data", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for item in items {
                let menuItem = NSMenuItem(title: "\(item.name)  (\(item.count.string))", action: nil, keyEquivalent: "")
                menuItem.isEnabled = false
                submenu.addItem(menuItem)
            }
        }
    }
}
```

- [ ] **Step 4b: Add menuDidClose to reset fetch flag**

This ensures rapid menu re-opens can trigger a fresh fetch:

```swift
func menuDidClose(_ menu: NSMenu) {
    guard menu == mainMenu else { return }
    isFetchingTopItems = false
}
```

- [ ] **Step 5: Update clearSubmenus() to clear new caches**

In the existing `clearSubmenus()` method (around line 630), add at the end before the closing brace:

```swift
cachedTopBlocked.removeAll()
cachedTopClients.removeAll()
```

- [ ] **Step 6: Build to verify**

Run: `xcodebuild -project PiGuard.xcodeproj -scheme PiGuard build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add PiGuard/Views/Main\ Menu/MainMenu.xib PiGuard/Views/Main\ Menu/MainMenuController.swift
git commit -m "feat: add top blocked and top clients submenus to menu bar"
```

---

## Task 6: Query Log Window

**Files:**
- Create: `PiGuard/Views/QueryLog/QueryLogWindowController.swift`
- Create: `PiGuard/Views/QueryLog/QueryLogViewController.swift`
- Modify: `PiGuard/Views/Main Menu/MainMenuController.swift`
- Modify: `PiGuard.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create QueryLogWindowController.swift**

```swift
//
//  QueryLogWindowController.swift
//  PiGuard
//

import Cocoa

final class QueryLogWindowController: NSWindowController {
    convenience init(piholes: [String: Pihole]) {
        let viewController = QueryLogViewController(piholes: piholes)
        let window = NSWindow(contentViewController: viewController)
        window.title = "Query Log"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 800, height: 500))
        window.minSize = NSSize(width: 600, height: 300)
        window.center()
        self.init(window: window)
    }
}
```

- [ ] **Step 2: Create QueryLogViewController.swift — class shell + properties**

```swift
//
//  QueryLogViewController.swift
//  PiGuard
//

import Cocoa

final class QueryLogViewController: NSViewController {
    private let piholes: [String: Pihole]
    private var entries: [QueryLogEntry] = []
    private var filteredEntries: [QueryLogEntry] = []

    private let serverFilterPopup = NSPopUpButton()
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")

    private var isLoading = false

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init(piholes: [String: Pihole]) {
        self.piholes = piholes
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))

        // Server filter
        serverFilterPopup.removeAllItems()
        serverFilterPopup.addItem(withTitle: "All Servers")
        let sortedPiholes = piholes.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        for pihole in sortedPiholes {
            serverFilterPopup.addItem(withTitle: pihole.displayName)
            serverFilterPopup.lastItem?.representedObject = pihole.identifier
        }
        serverFilterPopup.target = self
        serverFilterPopup.action = #selector(filterChanged)

        refreshButton.target = self
        refreshButton.action = #selector(refreshAction)
        refreshButton.bezelStyle = .rounded

        statusLabel.textColor = .secondaryLabelColor

        // Toolbar row
        let toolbar = NSStackView(views: [serverFilterPopup, NSView(), statusLabel, refreshButton])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        // Table
        let timeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
        timeCol.title = "Time"
        timeCol.width = 140
        let domainCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("domain"))
        domainCol.title = "Domain"
        domainCol.width = 250
        let clientCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("client"))
        clientCol.title = "Client"
        clientCol.width = 120
        let statusCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusCol.title = "Status"
        statusCol.width = 80
        let serverCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("server"))
        serverCol.title = "Server"
        serverCol.width = 150

        tableView.addTableColumn(timeCol)
        tableView.addTableColumn(domainCol)
        tableView.addTableColumn(clientCol)
        tableView.addTableColumn(statusCol)
        tableView.addTableColumn(serverCol)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        // Context menu
        let contextMenu = NSMenu()
        contextMenu.addItem(NSMenuItem(title: "Allow Domain", action: #selector(allowDomainAction(_:)), keyEquivalent: ""))
        contextMenu.addItem(NSMenuItem(title: "Block Domain", action: #selector(blockDomainAction(_:)), keyEquivalent: ""))
        tableView.menu = contextMenu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(toolbar)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        fetchQueryLog()
    }
}
```

- [ ] **Step 3: Add fetch and filter logic**

Add these methods to QueryLogViewController:

```swift
// MARK: - Fetching

private func fetchQueryLog() {
    guard !isLoading else { return }
    isLoading = true
    statusLabel.stringValue = "Loading..."
    refreshButton.isEnabled = false

    let selectedIdentifier = serverFilterPopup.selectedItem?.representedObject as? String

    Task {
        var allEntries: [QueryLogEntry] = []
        for pihole in piholes.values {
            if let selectedIdentifier, pihole.identifier != selectedIdentifier { continue }
            if let api = pihole.api {
                allEntries.append(contentsOf: await api.fetchQueryLog())
            } else if let api6 = pihole.api6 {
                allEntries.append(contentsOf: await api6.fetchQueryLog())
            } else if let apiAdguard = pihole.apiAdguard {
                allEntries.append(contentsOf: await apiAdguard.fetchQueryLog())
            }
        }

        allEntries.sort { $0.timestamp > $1.timestamp }

        await MainActor.run {
            self.entries = allEntries
            self.applyFilter()
            self.statusLabel.stringValue = "\(self.filteredEntries.count) queries"
            self.refreshButton.isEnabled = true
            self.isLoading = false
        }
    }
}

private func applyFilter() {
    let selectedIdentifier = serverFilterPopup.selectedItem?.representedObject as? String

    if let selectedIdentifier {
        filteredEntries = entries.filter { $0.serverIdentifier == selectedIdentifier }
    } else {
        filteredEntries = entries
    }

    // Show/hide server column
    let serverCol = tableView.tableColumns.first { $0.identifier.rawValue == "server" }
    serverCol?.isHidden = selectedIdentifier != nil

    tableView.reloadData()
}

@objc private func filterChanged() {
    fetchQueryLog()
}

@objc private func refreshAction() {
    fetchQueryLog()
}
```

- [ ] **Step 4: Add allow/block context menu actions**

```swift
// MARK: - Allow / Block

@objc private func allowDomainAction(_ sender: NSMenuItem) {
    pushDomainRule(allow: true)
}

@objc private func blockDomainAction(_ sender: NSMenuItem) {
    pushDomainRule(allow: false)
}

private func pushDomainRule(allow: Bool) {
    let row = tableView.clickedRow
    guard row >= 0, row < filteredEntries.count else { return }
    let entry = filteredEntries[row]
    let domain = entry.domain
    let action = allow ? "Allow" : "Block"

    let targets = determineTargetServers()
    let serverNames = targets.map { $0.displayName }.joined(separator: ", ")

    let alert = NSAlert()
    alert.messageText = "\(action) \(domain)?"
    alert.informativeText = "This will be applied to: \(serverNames)"
    alert.addButton(withTitle: action)
    alert.addButton(withTitle: "Cancel")

    guard alert.runModal() == .alertFirstButtonReturn else { return }

    statusLabel.stringValue = "Applying..."

    Task {
        var results: [(String, Bool)] = []

        for pihole in targets {
            let success: Bool
            if let api = pihole.api {
                success = allow ? await api.allowDomain(domain) : await api.blockDomain(domain)
            } else if let api6 = pihole.api6 {
                success = allow ? await api6.allowDomain(domain) : await api6.blockDomain(domain)
            } else if let apiAdguard = pihole.apiAdguard {
                success = allow ? await apiAdguard.allowDomain(domain) : await apiAdguard.blockDomain(domain)
            } else {
                success = false
            }
            results.append((pihole.displayName, success))
        }

        await MainActor.run {
            let failures = results.filter { !$0.1 }
            if failures.isEmpty {
                self.statusLabel.stringValue = "\(action)ed \(domain)"
            } else {
                let failedNames = failures.map { $0.0 }.joined(separator: ", ")
                self.statusLabel.stringValue = "Failed on: \(failedNames)"
            }
        }
    }
}

private func determineTargetServers() -> [Pihole] {
    var targets: [Pihole] = []

    let v6Servers = piholes.values.filter { $0.backendType == .piholeV6 }
    let v5Servers = piholes.values.filter { $0.backendType == .piholeV5 }
    let adguardServers = piholes.values.filter { $0.backendType == .adguardHome }

    if v6Servers.count >= 2 && Preferences.standard.syncEnabled {
        // Push to primary only
        let primaryId = Preferences.standard.syncPrimaryIdentifier
        if let primary = v6Servers.first(where: { $0.identifier == primaryId }) {
            targets.append(primary)
        } else {
            targets.append(contentsOf: v6Servers)
        }
    } else {
        targets.append(contentsOf: v6Servers)
    }

    targets.append(contentsOf: v5Servers)
    targets.append(contentsOf: adguardServers)

    return targets
}
```

- [ ] **Step 5: Add NSTableViewDataSource and NSTableViewDelegate**

```swift
// MARK: - TableView

extension QueryLogViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEntries.count
    }
}

extension QueryLogViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredEntries.count, let column = tableColumn else { return nil }
        let entry = filteredEntries[row]

        let cellId = NSUserInterfaceItemIdentifier("QueryLogCell")
        let cell: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: cellId, owner: self) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField
            cell.identifier = cellId
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        switch column.identifier.rawValue {
        case "time":
            cell.textField?.stringValue = timeFormatter.string(from: entry.timestamp)
        case "domain":
            cell.textField?.stringValue = entry.domain
        case "client":
            cell.textField?.stringValue = entry.client
        case "status":
            cell.textField?.stringValue = entry.status.rawValue
            cell.textField?.textColor = entry.status == .blocked ? .systemRed : .labelColor
        case "server":
            cell.textField?.stringValue = entry.serverDisplayName
        default:
            break
        }

        return cell
    }
}
```

- [ ] **Step 6: Wire up Query Log menu action in MainMenuController**

Add a lazy property for the window controller and the action method:

```swift
private var queryLogWindowController: QueryLogWindowController?

@IBAction func queryLogAction(_: NSMenuItem) {
    guard let networkOverview = networkOverview else { return }
    if queryLogWindowController?.window?.isVisible == true {
        queryLogWindowController?.window?.makeKeyAndOrderFront(self)
    } else {
        queryLogWindowController = QueryLogWindowController(piholes: networkOverview.piholes)
        queryLogWindowController?.showWindow(self)
    }
    NSApp.activate(ignoringOtherApps: true)
}
```

- [ ] **Step 7: Create the QueryLog directory and add files to Xcode project**

```bash
mkdir -p "PiGuard/Views/QueryLog"
```

Add both new Swift files to the PBX project file under a new "QueryLog" group in the Views group.

- [ ] **Step 8: Build to verify**

Run: `xcodebuild -project PiGuard.xcodeproj -scheme PiGuard build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```bash
git add PiGuard/Views/QueryLog/ PiGuard/Views/Main\ Menu/MainMenuController.swift PiGuard.xcodeproj/project.pbxproj
git commit -m "feat: add query log window with server filter and allow/block actions"
```

---

## Task 7: Integration Verification

- [ ] **Step 1: Full build**

```bash
xcodebuild -project PiGuard.xcodeproj -scheme PiGuard build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED with no warnings related to our new code.

- [ ] **Step 2: Verify menu layout visually**

Run the app and check:
- "Top Blocked" appears after "Blocklist" with a submenu
- "Top Clients" appears after "Top Blocked" with a submenu
- "Query Log..." appears after "Top Clients"
- Submenus show "Loading..." initially, then populate when the menu opens
- For single-server setup: items listed directly
- For multi-server setup: server headers with separators

- [ ] **Step 3: Verify query log window**

- Click "Query Log..." to open the window
- Server filter shows "All Servers" plus each configured server
- Table populates with recent queries
- Switching the filter reloads data
- Right-click shows "Allow Domain" / "Block Domain"
- Confirmation dialog shows correct target servers

- [ ] **Step 4: Commit final state if any fixes were needed**

```bash
git add -A
git commit -m "fix: integration fixes for cross-platform stats and query log"
```
