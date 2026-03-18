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
- Current prerelease builds are packaged as direct macOS `.zip` downloads containing `PiBar.app`

## Download

- Next release candidate: `PiBar-2.0-rc1-macOS.zip`
- Current release candidate build: `684`
- Planned release tag: `macOS-v2.0-rc1`

Without a paid Apple Developer membership, the app is distributed as an unsigned `.app` inside a `.zip`. macOS will usually require a one-time manual approval in `Privacy & Security`.

## Installing The ZIP Build On macOS

1. Download `PiBar-2.0-rc1-macOS.zip`.
2. Double-click the ZIP to extract `PiBar.app`.
3. Drag `PiBar.app` to `/Applications`.
4. Try opening the app once.
5. If macOS blocks it, open `System Settings` -> `Privacy & Security`.
6. Click `Open Anyway` for PiBar.
7. Open `PiBar.app` again and confirm.

## Quick Start

1. Launch PiBar Enhanced.
2. Open the menu bar icon and choose Preferences.
3. Add your Pi-hole connection details.
4. Validate the connection and save it.
5. Add additional Pi-holes if you want failover visibility or sync.
6. Adjust display, shortcut, startup, polling, and sync settings to fit your setup.

## Release Process

- Build a release ZIP with `scripts/build-release-zip.sh --artifact-name PiBar-2.0-rc1-macOS`
- The script writes the archive to `build/release/`
- The archive contains `PiBar.app`
- Unsigned ZIP packaging is the default distribution path for this repository

### Create A Release Candidate

Use this workflow when cutting a new RC:

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Build the ZIP artifact:

```bash
scripts/build-release-zip.sh --artifact-name PiBar-2.0-rc1-macOS
```

3. Test the extracted app locally.
4. Commit the release-candidate version changes.
5. Tag the release candidate:

```bash
git tag -a macOS-v2.0-rc1 -m "macOS v2.0 RC 1"
```

6. Push the commit and tag.
7. Create a GitHub prerelease and upload `build/release/PiBar-2.0-rc1-macOS.zip`.

If you later join the Apple Developer Program, you can build the same app with a `Developer ID Application` certificate, notarize it, and replace the ZIP asset with a signed release artifact.

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
