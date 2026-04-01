# PiGuard Phase 9 Verification Plan

## Goal

Validate that the current `piguard` branch works correctly across:

- Pi-hole v5
- Pi-hole v6
- AdGuard Home
- mixed-backend environments
- sync gating and backend detection behavior

This plan is focused on release verification for the macOS app before any Windows follow-up work.

## Test Environment

Prepare as many of these as you can:

- 1 Pi-hole v5 server
- 2 Pi-hole v6 servers
- 1 AdGuard Home server
- 1 macOS machine running the current `PiGuard` build

Recommended labels:

- `pihole-v5-a`
- `pihole-v6-a`
- `pihole-v6-b`
- `adguard-a`

Record for each server:

- hostname or IP
- port
- HTTP or HTTPS
- credentials required
- expected admin URL

## Pre-Flight Checks

Before running backend-specific tests:

1. Launch PiGuard.
2. Open Preferences.
3. Confirm the app opens the PiGuard-branded About and Preferences windows.
4. Confirm existing saved servers still appear after the recent identifier and path cleanup.
5. Confirm the app still updates from the menu bar without crashing on startup.

Expected result:

- app launches normally
- Preferences opens normally
- About window shows current PiGuard branding and version
- no missing or duplicated saved connections after migration changes

## Test 1: Pi-hole v5

### Add Connection

1. Add a Pi-hole v5 server manually.
2. Enter hostname, port, SSL setting, token if required, and optional admin URL override.
3. Use `Test Connection`.
4. Save the connection.

Expected result:

- test succeeds with valid settings
- invalid token shows a clear failure
- saved server appears once in the server list
- admin URL opens the correct Pi-hole web UI

### Poll and Display

1. Wait for automatic polling or trigger a refresh cycle.
2. Observe the menu bar totals and submenu details.

Expected result:

- status updates to enabled, disabled, or offline correctly
- query and blocked counts populate
- blocklist count populates
- offline server is marked offline, not silently treated as zero

### Toggle Blocking

1. Disable blocking from the menu.
2. Re-enable blocking from the menu.

Expected result:

- status changes correctly
- menu labels remain correct for a Pi-hole-only setup
- no effect on unrelated saved servers

## Test 2: Pi-hole v6

### Add Connection

1. Add a Pi-hole v6 server manually.
2. Enter hostname, port, SSL setting, and app password.
3. Test connection.
4. Save the connection.

Expected result:

- valid app password succeeds
- invalid app password fails clearly
- blank password only works if the server actually allows unauthenticated access

### Poll and Display

1. Let PiGuard poll the v6 server.
2. Observe menu bar and submenus.

Expected result:

- query totals, blocked totals, percentage, and gravity count populate
- status reflects v6 blocking state correctly
- online and offline transitions are handled cleanly

### Toggle Blocking and Gravity

1. Disable blocking.
2. Re-enable blocking.
3. Trigger gravity update.

Expected result:

- blocking changes are reflected in the UI
- gravity update shows activity state in the menu bar
- no stuck “busy” state after completion

## Test 3: AdGuard Home

### Add Connection

1. Add an AdGuard Home server manually.
2. Enter hostname, port, SSL setting, username, and password.
3. Test connection.
4. Save the connection.

Expected result:

- missing hostname, port, username, or password is rejected before save
- invalid credentials show a useful auth failure
- valid credentials save successfully
- admin URL opens the AdGuard Home admin UI

### Poll and Display

1. Let PiGuard poll the AdGuard Home server.
2. Observe status and stats.

Expected result:

- protection status maps to enabled or disabled correctly
- DNS query count populates
- blocked count populates
- filter count populates from enabled filters
- unavailable Pi-hole-only fields do not break the UI

### Toggle Protection and Refresh Filters

1. Disable protection.
2. Re-enable protection.
3. Trigger filter refresh.

Expected result:

- protection changes succeed and update in the UI
- refresh action uses AdGuard filter refresh behavior
- activity state clears when complete

## Test 4: Backend Auto-Detection

Run detection against:

- one Pi-hole v5 server
- one Pi-hole v6 server
- one AdGuard Home server
- one invalid or unreachable endpoint

For each:

1. Open auto-detect flow.
2. Enter hostname, port, and SSL setting.
3. Run detection.

Expected result:

- Pi-hole v5 is detected as Pi-hole v5
- Pi-hole v6 is detected as Pi-hole v6
- AdGuard Home is detected as AdGuard Home, including auth-protected cases
- invalid endpoint shows a clean failure and allows manual selection

## Test 5: Mixed Networks

### What “Mixed Networks” Means

This means PiGuard is managing more than one backend type at the same time in one app session.

Examples:

- one Pi-hole v6 server plus one AdGuard Home server
- one Pi-hole v5 server plus one Pi-hole v6 server
- one Pi-hole v5 server plus one Pi-hole v6 server plus one AdGuard Home server

The goal is to verify that the app behaves correctly when these backends coexist, not just when each backend is tested alone.

### Scenarios

#### Scenario A: Pi-hole v6 + AdGuard Home

1. Save one Pi-hole v6 connection and one AdGuard Home connection.
2. Let both poll.
3. Open the menu and inspect labels.
4. Trigger blocking disable and re-enable.
5. Trigger refresh.

Expected result:

- both servers appear separately
- no server overwrites another due to identifier collisions
- menu uses generic wording like blocking and filters where appropriate
- refresh action handles both backends correctly

#### Scenario B: Same Hostname, Different Ports or Backends

1. Configure two entries sharing the same hostname but with different ports, protocols, or backend types.
2. Save both.
3. Let the app poll and display both.

Expected result:

- both entries remain distinct
- submenu entries stay separate
- web admin entries open the correct endpoint for each

#### Scenario C: One Server Offline, One Online

1. Keep one server reachable and make another unreachable.
2. Let polling run.

Expected result:

- one server shows online data
- one server shows offline
- aggregate network state reflects partial availability correctly

## Test 6: Sync Gating

### AdGuard and Legacy Exclusion

1. Save only AdGuard Home connections.
2. Save one Pi-hole v5 plus one AdGuard Home connection.
3. Save one Pi-hole v6 plus one AdGuard Home connection.
4. Save two Pi-hole v6 connections plus one AdGuard Home connection.

Expected result:

- sync stays hidden or unavailable until there are at least two Pi-hole v6 connections
- AdGuard Home and Pi-hole v5 are excluded from sync selection
- sync messaging explains why those connections are not eligible
- once two v6 servers exist, sync appears and only those v6 servers are selectable

## Test 7: Invalid Credentials and Error UX

Test each backend with bad credentials:

- Pi-hole v5 invalid token
- Pi-hole v6 invalid app password
- AdGuard invalid username or password

Expected result:

- test connection fails clearly
- save stays blocked when validation requires a successful test
- runtime polling failures do not crash the app
- failures are visible as offline, unauthorized, or connection errors rather than silent bad data

## Test 8: Regression Checks After Rename

1. Verify About window.
2. Verify Preferences window.
3. Verify menu bar app menu labels.
4. Verify build/release packaging still points at `PiGuard` paths.
5. Verify the app still reads existing saved preferences and credentials.

Expected result:

- no user-facing `PiBar` product naming remains in the active macOS app flow
- saved configuration still loads after folder, file, and manager renames

## Exit Criteria

Phase 9 is complete when:

- all three backends work independently
- mixed-backend scenarios pass
- sync is correctly limited to Pi-hole v6
- invalid credential handling is acceptable
- no backend collisions appear in saved connections or menus
- the macOS app builds and runs cleanly

## Suggested Test Log Format

For each scenario, record:

- date
- app commit or build
- servers used
- exact configuration
- pass or fail
- notes
- screenshot if UI behavior is unclear
