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
- Current prerelease builds are packaged as signed and notarized macOS `.dmg` downloads when Developer ID and notary credentials are available

## Download

- Next release candidate: `PiBar-2.0-rc1-macOS.dmg`
- Current release candidate build: `684`
- Planned release tag: `macOS-v2.0-rc1`

Unsigned ZIP packaging is still available for local testing, but the intended public release path is a signed and notarized DMG.

## Installing The DMG Build On macOS

1. Download `PiBar-2.0-rc1-macOS.dmg`.
2. Open the DMG.
3. Drag `PiBar.app` to `/Applications`.
4. Launch PiBar from `/Applications`.

If you are testing an unsigned ZIP instead of the notarized DMG, macOS may still require a one-time manual approval in `Privacy & Security`.

## Quick Start

1. Launch PiBar Enhanced.
2. Open the menu bar icon and choose Preferences.
3. Add your Pi-hole connection details.
4. Validate the connection and save it.
5. Add additional Pi-holes if you want failover visibility or sync.
6. Adjust display, shortcut, startup, polling, and sync settings to fit your setup.

## Release Process

- Build a release DMG with `scripts/build-release-dmg.sh --artifact-name PiBar-2.0-rc1-macOS`
- The script writes the installer to `build/release/`
- The DMG contains `PiBar.app` plus an `/Applications` shortcut
- The DMG workflow builds a signed app ZIP first, notarizes and staples the app, then signs and notarizes the DMG
- `scripts/build-release-zip.sh` remains available for local testing and intermediate notarization work

### Create A Release Candidate

Use this workflow when cutting a new RC:

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Build the signed and notarized DMG artifact:

```bash
scripts/build-release-dmg.sh \
  --artifact-name PiBar-2.0-rc1-macOS \
  --sign-identity 'Developer ID Application: Matthew Smith (GB7Z2TZ8LT)' \
  --notary-profile pibar-notary
```

3. Mount the DMG and test the installed app locally.
4. Commit the release-candidate version changes.
5. Tag the release candidate:

```bash
git tag -a macOS-v2.0-rc1 -m "macOS v2.0 RC 1"
```

6. Push the commit and tag.
7. Create a GitHub prerelease and upload `build/release/PiBar-2.0-rc1-macOS.dmg`.

### Set Up notarytool

1. Create an app-specific password for your Apple ID:
   https://appleid.apple.com/
2. Store notary credentials in your login keychain:

```bash
xcrun notarytool store-credentials pibar-notary \
  --apple-id "you@example.com" \
  --team-id "GB7Z2TZ8LT" \
  --password "app-specific-password"
```

3. Build, sign, notarize, staple, and repack the ZIP:

```bash
scripts/build-release-zip.sh \
  --artifact-name PiBar-2.0-rc1-macOS \
  --sign-identity 'Developer ID Application: Matthew Smith (GB7Z2TZ8LT)' \
  --notary-profile pibar-notary
```

4. Build the final signed and notarized DMG:

```bash
scripts/build-release-dmg.sh \
  --artifact-name PiBar-2.0-rc1-macOS \
  --sign-identity 'Developer ID Application: Matthew Smith (GB7Z2TZ8LT)' \
  --notary-profile pibar-notary
```

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
