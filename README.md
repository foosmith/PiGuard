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
- Current beta releases are packaged as direct macOS `.dmg` downloads

## Download

- Latest prerelease: [PiBar 1.2 Beta 2 for macOS](https://github.com/foosmith/pibar-enhanced/releases/download/macOS-v1.2-beta2/PiBar-1.2-beta2-macOS.dmg)
- Current beta build: `683`
- Release page: [macOS v1.2 Beta 2](https://github.com/foosmith/pibar-enhanced/releases/tag/macOS-v1.2-beta2)

## Quick Start

1. Launch PiBar Enhanced.
2. Open the menu bar icon and choose Preferences.
3. Add your Pi-hole connection details.
4. Validate the connection and save it.
5. Add additional Pi-holes if you want failover visibility or sync.
6. Adjust display, shortcut, startup, polling, and sync settings to fit your setup.

## Release Process

- Build a release DMG with `scripts/build-release-dmg.sh --artifact-name PiBar-1.2-beta2-macOS`
- The script writes the installer to `build/release/`
- `Apple Development` signing is suitable for testing and private sharing
- `Developer ID Application` signing and notarization are supported by the script when available

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
