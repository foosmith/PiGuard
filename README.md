# PiBar Enhanced for macOS

PiBar Enhanced is my macOS menu bar companion for Pi-hole. It keeps the important controls one click away, adds a practical Primary → Secondary sync workflow for Pi-hole v6, and smooths out the day-to-day usability details that make the app easier to live with.

This fork builds on the original PiBar idea and pushes it toward modern Pi-hole setups, especially homes and labs running multiple Pi-hole instances that need to stay aligned.

## What PiBar Enhanced Does

- Shows Pi-hole status and DNS activity from the macOS menu bar
- Supports multiple Pi-hole connections
- Works with Pi-hole v5 and older, plus Pi-hole v6
- Lets you enable or disable blocking without opening the web UI
- Includes optional Primary → Secondary sync for Pi-hole v6 environments
- Supports launch at login and a global keyboard shortcut for quick control
- Lets you tune refresh behavior with a configurable polling interval
- Includes opt-in diagnostic logging to a local log file for troubleshooting

## Sync Features

PiBar Enhanced now includes a built-in Primary → Secondary sync flow for Pi-hole v6.

- Choose a primary Pi-hole and a secondary Pi-hole
- Run sync on demand or on an interval
- Sync groups, adlists, and domains
- Preview changes with dry run mode before writing anything
- Optionally wipe secondary adlists before rebuilding from the primary
- Review recent sync status and activity from the app

This is aimed at real-world failover and mirrored DNS setups where keeping two Pi-hole v6 nodes in sync matters more than manually clicking through the web UI.

## Usability Improvements

- Pi-hole v6 connections now persist using the proper app password flow instead of an expired session token
- Launch at login is wired directly into preferences
- Keyboard shortcut preferences load and save correctly
- Polling preferences are easier to manage
- Sync Settings now uses a wider, sidebar-based layout that makes setup and activity easier to scan
- The menu bar now shows a visual in-progress indicator during sync and gravity updates
- Public macOS builds are packaged as signed and notarized `.dmg` downloads

## Download & Install

### Latest Release — beta 6 (build 689)

**[⬇ Download PiBar Enhanced — beta 6 (.dmg)](https://github.com/foosmith/pibar-enhanced/releases/download/v2.3-beta6/PiBar-Enhanced-2.3-beta6-macOS.dmg)**

Requires macOS 13 or later.

1. Download **PiBar-Enhanced-2.3-beta6-macOS.dmg**
2. Open the DMG — a window will appear showing PiBar-Enhanced.app and an Applications shortcut
3. Drag **PiBar-Enhanced.app** into the **Applications** folder
4. Eject the DMG (drag it to Trash or right-click → Eject)
5. Open **Launchpad** or your **Applications** folder and launch PiBar — it will appear in your menu bar

> **Gatekeeper on first launch:** This beta is signed and notarized, so macOS should open it normally after you drag it into **Applications**. If Finder still warns due to quarantine caching, eject the DMG, reopen it, and launch the copied app from **Applications**.

All releases are listed on the [Releases page](https://github.com/foosmith/pibar-enhanced/releases).

## About This Fork

PiBar Enhanced reflects the work I have been doing to make PiBar more useful for current Pi-hole deployments. The focus of this fork is straightforward:

- better Pi-hole v6 support
- practical sync tools for paired Pi-hole instances
- fewer setup annoyances
- cleaner release packaging for macOS users

If you are running multiple Pi-holes and want a lightweight native macOS control point, that is exactly what this project is being shaped for.

## Feedback

- Issues and feature requests: [GitHub Issues](https://github.com/foosmith/pibar-enhanced/issues)
- Release downloads and notes: [GitHub Releases](https://github.com/foosmith/pibar-enhanced/releases)

## Credits

- Original PiBar created by [Brad Root](https://github.com/amiantos)
- PiBar Enhanced maintained in this repository by [foosmith](https://github.com/foosmith)
- Pi-hole is a registered trademark of Pi-hole LLC
- This project is independent and is not affiliated with Pi-hole LLC
