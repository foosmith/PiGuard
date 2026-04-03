# Cross-Platform Stats & Query Log

## Overview

Add four features that work across all three backends (Pi-hole v5, Pi-hole v6, AdGuard Home):

1. **Top Blocked Domains** — submenu showing top 10 blocked domains per server
2. **Top Clients** — submenu showing top 10 clients per server
3. **Query Log Window** — standalone window listing recent DNS queries with server filter
4. **Quick Allow/Block** — push domain rules from the query log to servers

## Feature 1: Top Blocked Domains (Low Effort)

### Menu Structure

A new "Top Blocked" menu item in the main dropdown, positioned after the existing "Blocklist" item.

- **Single server:** Submenu lists top 10 domains with hit counts (e.g., `ads.example.com  (1,234)`)
- **Multiple servers:** Each server gets a labeled section in the submenu with a separator between servers, matching the per-server pattern used by existing stats.
- Items are display-only (no action on click).

### API Endpoints

| Backend | Endpoint | Response Shape |
|---------|----------|----------------|
| Pi-hole v5 | `GET /admin/api.php?auth=<token>&topItems` | `{ "top_ads": { "domain": count, ... } }` |
| Pi-hole v6 | `GET /api/stats/top_domains?blocked=true` | `{ "domains": [{ "domain": "...", "count": N }] }` |
| AdGuard Home | `GET /control/stats` | `{ "top_blocked_domains": [{ "domain": count }] }` |

### Data Model

```swift
struct TopItem {
    let name: String   // domain or client IP/hostname
    let count: Int
}
```

A single `TopItem` struct is reused for both top blocked and top clients. Each API class gets a new method returning `[TopItem]`.

### Fetching Strategy

Top blocked/clients data is **not** fetched on every polling cycle. It is fetched **on demand** when the user opens the menu (`menuWillOpen` delegate). This avoids unnecessary API calls during normal polling. Results are cached until the next menu open.

## Feature 2: Top Clients (Low Effort)

### Menu Structure

A new "Top Clients" menu item, positioned after "Top Blocked".

- Same display pattern as Top Blocked: per-server sections in multi-server setups.
- Shows client IP or hostname with query count (e.g., `192.168.1.42  (5,678)`)

### API Endpoints

| Backend | Endpoint | Response Shape |
|---------|----------|----------------|
| Pi-hole v5 | `GET /admin/api.php?auth=<token>&topClients` | `{ "top_sources": { "client": count, ... } }` |
| Pi-hole v6 | `GET /api/stats/top_clients` | `{ "clients": [{ "name": "...", "count": N }] }` |
| AdGuard Home | `GET /control/stats` | `{ "top_clients": [{ "client": count }] }` |

### Data Model

Reuses `TopItem` from Feature 1.

## Feature 3: Query Log Window (Medium Effort)

### Window Design

A standalone `NSWindow` opened from a new "Query Log" menu item (positioned after Top Clients). The window contains:

- **Server filter dropdown** at the top — defaults to "All Servers", lists each configured server by display name.
- **Table view** with columns: Time, Domain, Client, Status (Allowed/Blocked), Server.
  - The "Server" column is hidden when a specific server is selected in the filter.
- **Refresh button** to re-fetch.
- Fetches the most recent 100 queries on open (or per-server limit if the API imposes one).

### API Endpoints

| Backend | Endpoint | Response Shape |
|---------|----------|----------------|
| Pi-hole v5 | `GET /admin/api.php?auth=<token>&getAllQueries=100` | `{ "data": [["timestamp", "type", "domain", "client", "status", ...], ...] }` |
| Pi-hole v6 | `GET /api/queries?length=100` | `{ "queries": [{ "time": N, "domain": "...", "client": { "ip": "..." }, "status": "..." }] }` |
| AdGuard Home | `GET /control/querylog?limit=100` | `{ "data": [{ "time": "...", "QH": "...", "IP": "...", "reason": "..." }] }` |

### Data Model

```swift
struct QueryLogEntry {
    let timestamp: Date
    let domain: String
    let client: String
    let status: QueryLogStatus
    let serverIdentifier: String
    let serverDisplayName: String
}

enum QueryLogStatus: String {
    case allowed = "Allowed"
    case blocked = "Blocked"
}
```

Each API class gets a `fetchQueryLog(limit:) async throws -> [QueryLogEntry]` method that normalizes the backend-specific response into this common model.

### Fetching

Queries are fetched when the window opens and when the user clicks Refresh. Not polled automatically.

## Feature 4: Quick Allow/Block (Medium Effort)

### UI

In the query log table, each row has two small buttons or a right-click context menu:
- **Allow** — adds the domain to the allowlist
- **Block** — adds the domain to the blocklist

A confirmation alert shows before pushing: "Block example.com on 2 servers?" with the list of target servers.

After a successful push, a brief inline status shows "Added" next to the domain.

### Multi-Server Push Logic

| Scenario | Behavior |
|----------|----------|
| Single server | Push to that server |
| Multiple Pi-hole v6, sync enabled | Push to primary only |
| Multiple Pi-hole v6, sync disabled | Push to ALL v6 servers |
| Multiple Pi-hole v5 | Push to ALL v5 servers |
| Multiple AdGuard Home | Push to ALL AdGuard servers |
| Mixed backends | Push to all servers of each backend type independently |

"Sync enabled" means `Preferences.standard.syncEnabled == true`.

### API Endpoints

| Backend | Action | Endpoint |
|---------|--------|----------|
| Pi-hole v5 | Allow | `GET /admin/api.php?auth=<token>&list=white&add=<domain>` |
| Pi-hole v5 | Block | `GET /admin/api.php?auth=<token>&list=black&add=<domain>` |
| Pi-hole v6 | Allow | `POST /api/domains/allow/exact` body: `{ "domain": "...", "comment": "Added via PiGuard" }` |
| Pi-hole v6 | Block | `POST /api/domains/deny/exact` body: `{ "domain": "...", "comment": "Added via PiGuard" }` |
| AdGuard Home | Allow | `POST /control/filtering/remove_url` or add to custom allowlist rules |
| AdGuard Home | Block | `POST /control/filtering/add_url` or add custom rule `\|\|domain^` via `POST /control/filtering/set_rules` |

Note: AdGuard Home's allow/block uses custom filtering rules rather than separate list endpoints. The implementation will append `@@\|\|domain^` (allow) or `\|\|domain^` (block) to the user's custom rules via the filtering API.

## Architecture

### New Files

| File | Purpose |
|------|---------|
| `PiGuard/Views/QueryLog/QueryLogWindowController.swift` | Window controller for the query log |
| `PiGuard/Views/QueryLog/QueryLogViewController.swift` | Table view, filter dropdown, refresh button, allow/block actions |

### Modified Files

| File | Changes |
|------|---------|
| `PiholeAPI.swift` | Add `fetchTopBlocked()`, `fetchTopClients()`, `fetchQueryLog()`, `allowDomain()`, `blockDomain()` |
| `Pihole6API.swift` | Add `fetchTopBlocked()`, `fetchTopClients()`, `fetchQueryLog()`, `allowDomain()`, `blockDomain()` |
| `AdGuardHomeAPI.swift` | Add `fetchTopBlocked()`, `fetchTopClients()`, `fetchQueryLog()`, `allowDomain()`, `blockDomain()` |
| `Structs.swift` | Add `TopItem`, `QueryLogEntry`, `QueryLogStatus` |
| `MainMenuController.swift` | Add Top Blocked, Top Clients, and Query Log menu items; on-demand fetch in `menuWillOpen`; open query log window action |
| `Pihole` struct in `Structs.swift` | No changes needed — the API objects are already accessible |

### Menu Layout (Updated)

```
Status: Enabled
Queries: 12,345
Blocked: 1,234 (10.0%)
Blocklist: 150,000
Top Blocked              >  [per-server submenu]
Top Clients              >  [per-server submenu]
---
Query Log...                [opens window]
---
Disable Blocking         >
Enable Blocking
---
Refresh Filters / Update Gravity
Sync Settings...
Sync Now
---
Admin Console
Preferences...
About PiGuard
Quit
```

## Testing

- Single Pi-hole v5 server: verify all four features work
- Single Pi-hole v6 server: verify all four features work
- Single AdGuard Home server: verify all four features work
- Multi-server (same type): verify per-server submenus and push-to-all behavior
- Multi-server with sync enabled: verify push-to-primary-only behavior
- Mixed backends: verify independent per-type push
- Offline server: verify graceful handling (empty submenus, error on push)
