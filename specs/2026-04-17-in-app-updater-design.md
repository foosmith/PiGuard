# In-App Updater Design

**Date:** 2026-04-17
**Status:** Approved

## Overview

Add a "Check for Updates" menu item to PiGuard's macOS menu bar app. When triggered, Sparkle downloads and installs the update in-app. An optional automatic check on launch is available but off by default.

## Section 1: Sparkle Integration

**Framework:** Sparkle 2.x via Swift Package Manager.

**Sandbox support:** Because PiGuard is sandboxed (`com.apple.security.app-sandbox = true`), Sparkle 2 requires two XPC helper bundles embedded in the app bundle:
- `Sparkle Helper (Installer).app`
- `Sparkle Helper (UI).app`

These are added to a Copy Files build phase (Destination: Wrapper, subpath empty) in Xcode. Each helper also needs its own entitlements file — Sparkle provides these.

**Info.plist additions:**
- `SUFeedURL` → `https://foosmith.github.io/PiGuard/appcast.xml`
- `SUPublicEDKey` → EdDSA public key (generated once locally)

**UpdateManager:** A new `UpdateManager.swift` class wraps `SPUStandardUpdaterController`. It exposes:
- `checkForUpdates()` — user-initiated, shows Sparkle's standard update window
- `checkForUpdatesInBackground()` — called on launch when the preference is enabled (Sparkle suppresses UI if no update is found)

**One-time key setup:**
1. Run `./bin/generate_keys` from the Sparkle package to generate an EdDSA key pair
2. The private key is saved to your macOS Keychain automatically
3. The public key is printed — copy it into `Info.plist` as `SUPublicEDKey`
4. Export the private key and store it as a GitHub Actions secret named `SPARKLE_PRIVATE_KEY`

## Section 2: UI Changes

**Menu bar menu:** A "Check for Updates…" item is added to the status bar right-click menu. It calls `UpdateManager.shared.checkForUpdates()`. Sparkle owns all update UI (release notes sheet, download progress, relaunch prompt).

**Preferences window:** A new checkbox row is added to the existing Preferences window:
- Label: "Automatically check for updates on launch"
- Default: unchecked (off)
- Stored in `UserDefaults` under key `automaticallyCheckForUpdates`

**AppDelegate:** On `applicationDidFinishLaunching`, reads the preference and calls `UpdateManager.shared.checkForUpdatesInBackground()` if enabled.

## Section 3: Appcast Hosting

**Branch:** `gh-pages` in the same repo, served at `https://foosmith.github.io/PiGuard/`.

**File:** `appcast.xml` at the root of the branch.

**Format:** Sparkle RSS appcast. Each `<item>` contains:
- `<title>` — version string (e.g. "PiGuard 3.2")
- `<pubDate>` — release date
- `<sparkle:version>` — build number (CFBundleVersion)
- `<sparkle:shortVersionString>` — marketing version
- `<sparkle:minimumSystemVersion>` — minimum macOS version
- `<enclosure url="…" length="…" type="application/octet-stream" sparkle:edSignature="…">` — DMG URL, byte size, EdDSA signature
- `<description>` — release notes as HTML

**Retention:** All past items are kept. The GHA workflow prepends new items so older clients receive the correct update path.

## Section 4: GitHub Actions Workflow

**File:** `.github/workflows/update-appcast.yml`

**Trigger:** `on: release: types: [published]`

**Steps:**

1. **Download Sparkle tools** — fetch the Sparkle release ZIP matching the SPM version, extract `sign_update` binary
2. **Checkout gh-pages** — `actions/checkout` with `ref: gh-pages`
3. **Download release DMG** — use `gh release download` with the tag from the event to fetch the `.dmg` asset
4. **Sign DMG** — run `sign_update <dmg-path>` with `SPARKLE_PRIVATE_KEY` env var; capture the EdDSA signature output
5. **Get release metadata** — use GitHub API (`gh release view`) to fetch tag name, release name, body (release notes), and published date; convert Markdown body to HTML via a small Python script
6. **Get DMG file size** — `stat -f%z` on the downloaded DMG
7. **Prepend appcast item** — Python/bash script inserts a new `<item>` block before the first existing `<item>` in `appcast.xml` (or creates the file if absent)
8. **Commit and push** — commit `appcast.xml` to `gh-pages` with message `chore: update appcast for <tag>`

**Required secrets:**
- `SPARKLE_PRIVATE_KEY` — EdDSA private key exported from local Keychain

**Required permissions:**
- `contents: write` — to push to gh-pages
- `GITHUB_TOKEN` is sufficient for the GitHub API calls

## Files Changed / Created

| File | Change |
|------|--------|
| `mac/PiGuard.xcodeproj/project.pbxproj` | Add Sparkle SPM dependency, Copy Files build phase for XPC helpers |
| `mac/PiGuard/Info.plist` | Add `SUFeedURL`, `SUPublicEDKey` |
| `mac/PiGuard/Manager/UpdateManager.swift` | New — wraps `SPUStandardUpdaterController` |
| `mac/PiGuard/AppDelegate.swift` | Call `checkForUpdatesInBackground()` on launch if preference enabled |
| `mac/PiGuard/Views/Main Menu/StatusMenuController.swift` | Add "Check for Updates…" menu item |
| `mac/PiGuard/Views/Preferences/PreferencesViewController.swift` | Add auto-update checkbox |
| `.github/workflows/update-appcast.yml` | New — automates appcast on release |
| `gh-pages` branch: `appcast.xml` | New branch + file |

## Out of Scope

- Delta/binary diffs (full DMG replacement only)
- Windows version (separate project)
- App Store distribution (uses Apple's own update mechanism)
