# PiGuard Plan

## Summary

PiGuard is a single menu bar app that can monitor and control both Pi-hole and AdGuard Home instances.

Core goals:

- Show DNS blocker status and stats in the menu bar
- Enable or disable blocking
- Refresh filters or gravity
- Support mixed Pi-hole and AdGuard Home networks from one app

This work is isolated on the `piguard` branch so `master` stays untouched.

## Backend Scope

Planned backend support:

- `Pi-hole v5`
- `Pi-hole v6`
- `AdGuard Home`

Shared direction:

- Keep existing Pi-hole clients
- Add a dedicated AdGuard Home client
- Normalize server selection around a `BackendType` enum and a V4 connection model

## API Mapping

| Feature | Pi-hole v5/v6 | AdGuard Home | Notes |
| --- | --- | --- | --- |
| Total queries | Direct field | `/control/stats -> num_dns_queries` | Direct map |
| Blocked queries | Direct field | `num_blocked_filtering` | Direct map |
| % blocked | Direct or computed | Computed client-side | Minor |
| Blocklist size | Direct field | Sum `rules_count` from `/control/filtering/status` | Extra call |
| Status | `status` / `blocking` | `/control/status -> protection_enabled` | Direct map |
| Enable or disable | API call | `POST /control/protection` | Direct map |
| Timed disable | Seconds | Milliseconds | Unit conversion |
| Filter refresh | Gravity update | `POST /control/filtering/refresh` | Direct map |
| Auth | Token or session | HTTP Basic Auth | Simpler |
| Unique domains | Available | Not available | Show `N/A` or zero-backed data |
| Forwarded or cached | Available | Not available | Show `N/A` or zero-backed data |
| Sync | Built-in for v6 | Not supported here | Deferred |

## Phases

### Phase 0: Branch and Rebrand

1. Create the `piguard` branch from `master`.
2. Rename user-facing branding to `PiGuard`.
3. Update bundle and keychain identifiers.
4. Adjust target or project naming pragmatically.
5. Verify the renamed app still builds.

### Phase 1: Backend Type and Connection Model

1. Add `BackendType` with `piholeV5`, `piholeV6`, and `adguardHome`.
2. Replace `isV6` persistence with `PiholeConnectionV4`.
3. Add `username` for AdGuard Home credentials.
4. Migrate stored connections from V3 to V4.
5. Update runtime `Pihole` state to carry `backendType` and an AdGuard client reference.

### Phase 2: AdGuard Home API Client

Create `PiGuard/Data Sources/AdGuardHomeAPI.swift` with support for:

- `GET /control/status`
- `GET /control/stats`
- `GET /control/filtering/status`
- `POST /control/protection`
- `POST /control/filtering/refresh`

### Phase 3: AdGuard Update Operation

Create `PiGuard/Manager/Operations/UpdateAdGuardHomeOperation.swift` to:

- Fetch status, stats, and filtering data
- Map the results into `PiholeAPISummary`
- Update online and enabled state

### Phase 4: Manager Integration

Update `PiGuard/Manager/PiGuardManager.swift` and `PiGuard/Manager/Operations/ChangePiholeStatusOperation.swift` to:

- Create AdGuard-backed runtime nodes
- Poll them with a dedicated update operation
- Route enable or disable calls to the correct backend
- Refresh AdGuard filters during network-wide refresh

### Phase 5: Settings UI

Create `PiGuard/Views/Preferences/AdGuardHomeSettingsViewController.swift` for:

- Hostname
- Port
- SSL toggle
- Username
- Password
- Test connection
- Generated admin panel URL

### Phase 6: Auto-Detection

Create `PiGuard/Utilities/BackendDetector.swift` to probe:

- `GET /admin/api.php?summaryRaw`
- `POST /api/auth`
- `GET /control/status`

The first matching response determines backend type.

### Phase 7: Menu Label Adjustments

Genericize menu labels when AdGuard Home nodes are present:

- `Disable Blocking`
- `Enable Blocking`
- `Refresh Filters` or equivalent mixed wording later

### Phase 8: Windows

Deferred until the macOS implementation is validated.

### Phase 9: Verification

1. Build the macOS app.
2. Re-test Pi-hole v5.
3. Re-test Pi-hole v6.
4. Test AdGuard Home add, poll, toggle, and refresh flows.
5. Test backend auto-detection.
6. Test mixed networks.
7. Verify sync remains hidden or disabled for AdGuard Home.
8. Verify invalid credentials show a useful error.

## Current Scaffold In This Branch

This branch now includes an initial structural pass:

- `BackendType` enum
- `PiholeConnectionV4` model and preference migration
- `AdGuardHomeAPI.swift`
- `UpdateAdGuardHomeOperation.swift`
- `BackendDetector.swift`
- `AdGuardHomeSettingsViewController.swift`
- Manager and status-operation routing for AdGuard-aware backends

This is foundation work only. Branding, storyboard wiring, Xcode target renaming, and full validation are still pending.
