# Cross-Platform Stats & Query Log

## Overview

Add four features that work across all three backends (Pi-hole v5, Pi-hole v6, AdGuard Home):

1. **Top Blocked Domains** — submenu showing top 10 blocked domains per server
2. **Top Clients** — submenu showing top 10 clients per server
3. **Query Log Window** — standalone window listing recent DNS queries with server filter
4. **Quick Allow/Block** — push domain rules from the query log to servers

## Async Pattern Note

Pi-hole v5 (`PiholeAPI`) uses completion handlers. Pi-hole v6 (`Pihole6API`) and AdGuard Home (`AdGuardHomeAPI`) use `async/await`. New v5 methods will use `withCheckedContinuation` to wrap the existing completion-handler-based `get()` method, providing a uniform `async throws` interface for callers.

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
| AdGuard Home | `GET /control/stats` | `{ "top_blocked_domains": [{"domain": count}, ...] }` — array of single-key dictionaries |

Note: AdGuard Home returns `top_blocked_domains` and `top_clients` as arrays of single-key dictionaries (e.g., `[{"ads.example.com": 1234}]`), not standard keyed objects. The decoder must handle this shape.

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

**`menuWillOpen` integration details:**
- A `Bool` flag (`isFetchingTopItems`) prevents concurrent fetches if the user opens the menu rapidly.
- While fetching, the submenu shows a single disabled item: "Loading..."
- If the fetch fails or the server is offline, the submenu shows: "Unavailable"
- Fetched results are stored in dictionaries keyed by server identifier, cleared on next `menuWillOpen`.

## Feature 2: Top Clients (Low Effort)

### Menu Structure

A new "Top Clients" menu item, positioned after "Top Blocked".

- Same display pattern as Top Blocked: per-server sections in multi-server setups.
- Shows client IP or hostname with query count (e.g., `192.168.1.42  (5,678)`)
- Pi-hole v6 responses include a `name` field alongside `ip` — prefer `name` when available.

### API Endpoints

| Backend | Endpoint | Response Shape |
|---------|----------|----------------|
| Pi-hole v5 | `GET /admin/api.php?auth=<token>&topClients` | `{ "top_sources": { "client": count, ... } }` |
| Pi-hole v6 | `GET /api/stats/top_clients` | `{ "clients": [{ "name": "...", "ip": "...", "count": N }] }` |
| AdGuard Home | `GET /control/stats` | `{ "top_clients": [{"client": count}, ...] }` — array of single-key dictionaries |

### Data Model

Reuses `TopItem` from Feature 1.

## Feature 3: Query Log Window (Medium Effort)

### Window Design

A standalone `NSWindow` opened from a new "Query Log..." menu item (positioned after Top Clients). The window contains:

- **Server filter dropdown** at the top — defaults to "All Servers", lists each configured server by display name.
- **Table view** with columns: Time, Domain, Client, Status (Allowed/Blocked), Server.
  - The "Server" column uses `NSTableColumn.isHidden = true` when a specific server is selected in the filter.
- **Refresh button** to re-fetch.
- Fetches the most recent 100 queries on open (or per-server limit if the API imposes one).
- **Sort order:** Displayed newest-first. Client-side sort by timestamp after merging results from multiple servers.

### API Endpoints

| Backend | Endpoint | Response Shape |
|---------|----------|----------------|
| Pi-hole v5 | `GET /admin/api.php?auth=<token>&getAllQueries=100` | `{ "data": [[timestamp, type, domain, client, status_code, ...], ...] }` |
| Pi-hole v6 | `GET /api/queries?length=100` | `{ "queries": [{ "time": N, "domain": "...", "client": { "ip": "...", "name": "..." }, "status": "..." }] }` |
| AdGuard Home | `GET /control/querylog?limit=100` | `{ "data": [{ "time": "...", "QH": "...", "IP": "...", "reason": "..." }] }` |

### Pi-hole v5 Query Array Indices

The v5 `getAllQueries` response returns arrays where position matters:
- Index 0: timestamp (Unix epoch as string)
- Index 1: query type (A, AAAA, etc.)
- Index 2: domain
- Index 3: client IP/hostname
- Index 4: status code (integer)

### Status Code Mapping

All backends return richer status than just allowed/blocked. The mapping to `QueryLogStatus`:

**Pi-hole v5 status codes:**
- Blocked (1, 4, 5, 6, 7, 8, 9, 10, 11): gravity, regex, denylist, external blocked, CNAME variants
- Allowed (2, 3, 12, 13, 14): forwarded, cached, retried, already-in-database

**Pi-hole v6 status strings:**
- Blocked: GRAVITY, REGEX, DENYLIST, EXTERNAL_BLOCKED_*, GRAVITY_CNAME, REGEX_CNAME, DENYLIST_CNAME
- Allowed: FORWARDED, CACHE, CACHE_STALE, RETRIED, RETRIED_DNSSEC, SPECIAL_DOMAIN

**AdGuard Home `reason` field:**
- Blocked: FilteredBlackList, FilteredBlockedService, FilteredParental, FilteredSafeBrowsing, FilteredSafeSearch
- Allowed: NotFilteredNotFound, NotFilteredWhiteList, NotFilteredError

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

Each API class gets a `fetchQueryLog(limit:) async throws -> [QueryLogEntry]` method that normalizes the backend-specific response into this common model. The server identifier and display name are set by the caller, not the API class.

### Fetching

Queries are fetched when the window opens and when the user clicks Refresh. Not polled automatically.

## Feature 4: Quick Allow/Block (Medium Effort)

### UI

In the query log table, each row has a right-click context menu:
- **Allow Domain** — adds the domain to the allowlist
- **Block Domain** — adds the domain to the blocklist

A confirmation alert shows before pushing: "Block example.com on 2 servers?" with the list of target servers.

After a successful push, a brief inline status shows "Added" next to the domain. On partial failure, show which servers succeeded and which failed (e.g., "Added to server1. Failed on server2: connection error").

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
| AdGuard Home | Allow | Read-modify-write via custom filtering rules (see below) |
| AdGuard Home | Block | Read-modify-write via custom filtering rules (see below) |

### AdGuard Home Custom Rules

AdGuard Home does not have separate allow/block list endpoints for individual domains. Instead, use the custom filtering rules API:

1. `GET /control/filtering/status` — read current `user_rules` string array
2. Append `@@||domain^` (allow) or `||domain^` (block) to the array
3. `POST /control/filtering/set_rules` — write the updated rules

This is a read-modify-write pattern. To prevent race conditions if the user clicks rapidly, the allow/block buttons are disabled while a push is in progress.

## Architecture

### New Files

| File | Purpose |
|------|---------|
| `PiGuard/Views/QueryLog/QueryLogWindowController.swift` | Window controller for the query log |
| `PiGuard/Views/QueryLog/QueryLogViewController.swift` | Table view, filter dropdown, refresh button, allow/block actions |

### Modified Files

| File | Changes |
|------|---------|
| `PiholeAPI.swift` | Add async wrappers via `withCheckedContinuation`; add `fetchTopBlocked()`, `fetchTopClients()`, `fetchQueryLog()`, `allowDomain()`, `blockDomain()` |
| `Pihole6API.swift` | Add `fetchTopBlocked()`, `fetchTopClients()`, `fetchQueryLog()`, `allowDomain()`, `blockDomain()` |
| `AdGuardHomeAPI.swift` | Add `fetchTopBlocked()`, `fetchTopClients()`, `fetchQueryLog()`, `allowDomain()`, `blockDomain()` |
| `Structs.swift` | Add `TopItem`, `QueryLogEntry`, `QueryLogStatus` |
| `MainMenuController.swift` | Add Top Blocked, Top Clients, and Query Log menu items; `menuWillOpen` on-demand fetch with loading state; open query log window action; update `clearSubmenus()` to handle new submenus |

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
- Partial failure on multi-server push: verify per-server success/failure reporting
- Rapid menu opens: verify no duplicate concurrent fetches
