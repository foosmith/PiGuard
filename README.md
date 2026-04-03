# PiGuard for macOS

PiGuard is a macOS menu bar companion for DNS filtering servers. It keeps the important controls one click away, adds a practical Primary → Secondary sync workflow for Pi-hole v6, and is being extended to work across mixed Pi-hole and AdGuard Home environments.

This fork builds on the original PiBar idea and pushes it toward modern home-lab DNS setups, especially networks running multiple filtering servers that need to stay aligned.

## What PiGuard Does

- Shows blocking status and DNS activity from the macOS menu bar
- Supports multiple server connections
- Supports Pi-hole v5 and older
- Supports Pi-hole v6
- Adds AdGuard Home integration work for mixed-backend deployments
- Lets you enable or disable blocking without opening the web UI
- Refreshes Pi-hole gravity or AdGuard Home filters from the menu bar
- Includes optional Primary → Secondary sync for Pi-hole v6 environments
- Supports launch at login and a global keyboard shortcut for quick control
- Lets you tune refresh behavior with a configurable polling interval
- Includes opt-in diagnostic logging to a local log file for troubleshooting

## AdGuard Home Status

PiGuard is the branch and product direction for bringing AdGuard Home into the app alongside Pi-hole.

Current AdGuard Home work in this repo includes:

- backend detection support
- an AdGuard Home API client
- polling and status normalization
- blocking enable or disable actions
- filter refresh support
- connection settings UI
- mixed-backend menu wording updates

The remaining work is validation, polish, and finishing the broader rename and packaging sweep around the new PiGuard identity.

## Sync Features

PiGuard includes a built-in Primary → Secondary sync flow for Pi-hole v6.

- Choose a primary Pi-hole and a secondary Pi-hole
- Run sync on demand or on an interval
- Sync groups, adlists, and domains
- Preview changes with dry run mode before writing anything
- Optionally wipe secondary adlists before rebuilding from the primary
- Review recent sync status and activity from the app

This is aimed at real-world failover and mirrored DNS setups where keeping two Pi-hole v6 nodes in sync matters more than manually clicking through the web UI.

## Usability Improvements

- Pi-hole v6 connections now persist using the proper app password flow instead of an expired session token
- AdGuard Home connections can be modeled with their own backend-aware settings flow
- Launch at login is wired directly into preferences
- Keyboard shortcut preferences load and save correctly
- Polling preferences are easier to manage
- Sync Settings now uses a taller full-width layout with a bottom status band, wider activity log, and inline help popovers for advanced settings
- The menu bar now shows a visual in-progress indicator during sync and refresh operations
- Public macOS builds are packaged as signed and notarized `.dmg` downloads

## Download & Install

### Current Public Build — Beta (build 695)

**[⬇ Download current beta DMG](https://github.com/foosmith/PiGuard/releases/download/v2.3-beta9/PiGuard-2.3-beta9-macOS.dmg)**

Requires macOS 13 or later.

1. Download **PiGuard-2.3-beta9-macOS.dmg**
2. Open the DMG. A window will appear showing the app and an Applications shortcut.
3. Drag the app into the **Applications** folder.
4. Eject the DMG (drag it to Trash or right-click → Eject)
5. Open **Launchpad** or your **Applications** folder and launch PiGuard. It will appear in your menu bar.

> **Gatekeeper on first launch:** This beta is signed and notarized, so macOS should open it normally after you drag it into **Applications**. If Finder still warns due to quarantine caching, eject the DMG, reopen it, and launch the copied app from **Applications**.

All releases are listed on the [Releases page](https://github.com/foosmith/PiGuard/releases).

## About This Fork

PiGuard reflects the work I have been doing to evolve PiBar into a broader macOS control point for current DNS filtering deployments. The focus of this repo is straightforward:

- better Pi-hole v6 support
- practical sync tools for paired Pi-hole instances
- first-class mixed-network support for Pi-hole and AdGuard Home
- fewer setup annoyances
- cleaner release packaging for macOS users

If you are running multiple DNS filtering servers and want a lightweight native macOS control point, that is exactly what this project is being shaped for.

## Feedback

- Issues and feature requests: [GitHub Issues](https://github.com/foosmith/PiGuard/issues)
- Release downloads and notes: [GitHub Releases](https://github.com/foosmith/PiGuard/releases)

## Credits

- Original PiBar created by [Brad Root](https://github.com/amiantos)
- PiGuard is maintained in this repository by [foosmith](https://github.com/foosmith)
- Pi-hole is a registered trademark of Pi-hole LLC
- AdGuard is a registered trademark of AdGuard Software Ltd
- This project is independent and is not affiliated with either company
