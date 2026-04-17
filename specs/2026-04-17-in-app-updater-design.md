# In-App Updater Design

**Date:** 2026-04-17
**Status:** Approved

## Overview

Add a "Check for Updates…" menu item to PiGuard's macOS menu bar app. When triggered, Sparkle downloads and installs the update in-app. An optional automatic check on launch is available but off by default.

## Section 1: Sparkle Integration

**Framework:** Sparkle 2.x via Swift Package Manager.

**Sandbox support:** Because PiGuard is sandboxed (`com.apple.security.app-sandbox = true`), Sparkle 2 requires two XPC helper bundles embedded in the app bundle:
- `Sparkle Helper (Installer).app`
- `Sparkle Helper (UI).app`

These are added to the main app target's **Copy Files** build phase (Destination: Wrapper, subpath empty) in Xcode. Each helper's entitlements are assigned in Xcode's Signing & Capabilities tab per helper target. The entitlements files Sparkle ships (`Sparkle Installer.entitlements` and `Sparkle UI.entitlements`) are found inside the SPM checkout under `checkouts/Sparkle/Sources/Sparkle/`. The main app's own entitlements file (`mac/PiGuard/PiGuard.entitlements`) requires no changes.

**Info.plist additions:**
- `SUFeedURL` → `https://foosmith.github.io/PiGuard/appcast.xml`
- `SUPublicEDKey` → EdDSA public key (generated once locally)

**ATS:** The appcast URL and GitHub releases DMG download URL are both HTTPS and will pass App Transport Security without any changes to `Info.plist`. No `NSAllowsArbitraryLoads` or ATS exceptions are needed.

**UpdateManager:** A new `UpdateManager.swift` class holds an `SPUStandardUpdaterController` instance. It exposes:
- `checkForUpdates()` — user-initiated; calls `updaterController.checkForUpdates(nil)`, which shows Sparkle's standard update window
- `checkForUpdatesInBackground()` — called on launch when the preference is enabled; calls `updaterController.updater.checkForUpdatesInBackground()` (note: this method is on `SPUUpdater`, accessed via `updaterController.updater`, not on `SPUStandardUpdaterController` directly). Sparkle suppresses UI if no update is found.

**One-time key setup:**
1. Run `./bin/generate_keys` from the Sparkle package to generate an EdDSA key pair
2. The private key is saved to your macOS Keychain automatically
3. The public key is printed — copy it into `Info.plist` as `SUPublicEDKey`
4. Export the private key (base64 string) and store it as a GitHub Actions secret named `SPARKLE_PRIVATE_KEY`

## Section 2: UI Changes

**Menu bar menu:** A "Check for Updates…" `NSMenuItem` is added to `MainMenu.xib` and wired as an `@IBOutlet` and `@IBAction` in `MainMenuController.swift` (consistent with the existing XIB-driven pattern used for all other menu items). The `@IBAction` calls `UpdateManager.shared.checkForUpdates()`.

**Preferences window:** A new checkbox row is added to the existing Preferences window:
- Label: "Automatically check for updates on launch"
- Default: unchecked (off)
- Stored via the existing `Preferences.standard` pattern: add `static let automaticallyCheckForUpdates = "SUEnableAutomaticChecks"` to `Preferences.Key`, register a default of `false` in `register(defaults:)`, and add a typed `var automaticallyCheckForUpdates: Bool` getter and `func set(automaticallyCheckForUpdates: Bool)` setter to the `UserDefaults` extension in `Preferences.swift` — matching the pattern used for all other settings (e.g. `hideMenuBarIcon`). Using Sparkle's own key (`SUEnableAutomaticChecks`) means Sparkle respects it natively in future, but since automatic checks in this design are launch-only (not interval-based), AppDelegate still gates the call manually rather than enabling Sparkle's built-in scheduler.

**AppDelegate:** On `applicationDidFinishLaunching`, reads `Preferences.standard.automaticallyCheckForUpdates` and calls `UpdateManager.shared.checkForUpdatesInBackground()` if `true`.

## Section 3: Appcast Hosting

**Prerequisites (one-time):**
1. Create a `gh-pages` branch in the repo: `git checkout --orphan gh-pages && git reset --hard && git commit --allow-empty -m "init" && git push origin gh-pages`
2. Enable GitHub Pages in repo Settings → Pages → Source: `gh-pages` branch, root folder
3. Commit the `appcast.xml` skeleton above to the root of the `gh-pages` branch; the GHA workflow requires this file to exist before its first run

**Branch:** `gh-pages` in the same repo, served at `https://foosmith.github.io/PiGuard/`.

**File:** `appcast.xml` at the root of the branch.

**Initial skeleton** (committed to the `gh-pages` branch as part of the one-time bootstrap step above — the GHA workflow depends on this file existing):
```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>PiGuard</title>
        <link>https://foosmith.github.io/PiGuard/appcast.xml</link>
        <description>PiGuard Changelog</description>
        <language>en</language>
    </channel>
</rss>
```

**Format:** Sparkle RSS appcast. Each `<item>` contains:
- `<title>` — version string (e.g. "PiGuard 3.2")
- `<pubDate>` — release date (RFC 2822)
- `<sparkle:version>` — build number (CFBundleVersion)
- `<sparkle:shortVersionString>` — marketing version
- `<sparkle:minimumSystemVersion>` — minimum macOS version
- `<enclosure url="…" length="…" type="application/octet-stream" sparkle:edSignature="…">` — DMG URL, byte size, EdDSA signature
- `<description><![CDATA[…]]></description>` — release notes as HTML

**Retention:** All past items are kept. The GHA workflow prepends new items inside the `<channel>` block so older clients receive the correct update path.

## Section 4: GitHub Actions Workflow

**File:** `.github/workflows/update-appcast.yml`

**Trigger:** `on: release: types: [published]`

**Runner:** `ubuntu-latest`

**Env vars (top of workflow):**
```yaml
env:
  SPARKLE_VERSION: "2.x.y"  # must match the version pinned in Package.resolved
```
This must be manually kept in sync with the SPM pin whenever Sparkle is updated.

**Steps:**

1. **Download Sparkle tools** — fetch `https://github.com/sparkle-project/Sparkle/releases/download/${{ env.SPARKLE_VERSION }}/Sparkle-${{ env.SPARKLE_VERSION }}.tar.bz2`, extract to get the `bin/sign_update` binary, make it executable
2. **Checkout gh-pages** — `actions/checkout` with `ref: gh-pages`
3. **Download release DMG** — `gh release download ${{ github.event.release.tag_name }} --pattern "*.dmg"` to fetch the `.dmg` asset
4. **Sign DMG** — run:
   ```bash
   SIGNATURE=$(echo "$SPARKLE_PRIVATE_KEY" | ./bin/sign_update <dmg-filename> --ed-key-file - -p)
   ```
   `--ed-key-file -` reads the base64 private key from stdin; `-p` (`--print-only-signature`) emits only the bare base64 signature, which is what the `sparkle:edSignature` attribute requires.
5. **Get release metadata** — `gh release view ${{ github.event.release.tag_name }} --json tagName,name,body,publishedAt` to fetch version info and release notes body (Markdown); convert body to HTML using Python's `markdown` library (`pip install markdown` in the step)
6. **Get DMG file size** — `stat -c%s <dmg-filename>` (Linux runner; produces the byte count)
7. **Prepend appcast item** — Python script inserts a new `<item>` block immediately before the first existing `<item>` in `appcast.xml`. If no `<item>` exists yet (first release), insert inside the `<channel>` element after `<language>`. The skeleton file is always present (committed in bootstrap step), so the script never needs to create the file from scratch.
8. **Commit and push** — commit `appcast.xml` to `gh-pages` with message `chore: update appcast for <tag>`

**Required secrets:**
- `SPARKLE_PRIVATE_KEY` — EdDSA private key (base64 string) exported from local Keychain

**Required permissions:**
```yaml
permissions:
  contents: write
```
`GITHUB_TOKEN` is sufficient for both the push to `gh-pages` and the GitHub API calls.

## Files Changed / Created

| File | Change |
|------|--------|
| `mac/PiGuard.xcodeproj/project.pbxproj` | Add Sparkle SPM dependency; add Copy Files build phase for XPC helpers; assign entitlements per helper target |
| `mac/PiGuard/Info.plist` | Add `SUFeedURL`, `SUPublicEDKey` |
| `mac/PiGuard/Manager/UpdateManager.swift` | New — wraps `SPUStandardUpdaterController` |
| `mac/PiGuard/AppDelegate.swift` | Call `UpdateManager.shared.checkForUpdatesInBackground()` on launch if `SUEnableAutomaticChecks` is true |
| `mac/PiGuard/Views/Main Menu/MainMenu.xib` | Add "Check for Updates…" `NSMenuItem` |
| `mac/PiGuard/Views/Main Menu/MainMenuController.swift` | Wire `@IBOutlet` and `@IBAction` for the new menu item |
| `mac/PiGuard/Data Sources/Preferences.swift` | Add `automaticallyCheckForUpdates` key, default (`false`), and typed accessor/setter |
| `mac/PiGuard/Views/Preferences/PreferencesViewController.swift` | Add auto-update checkbox bound to `automaticallyCheckForUpdates` |
| `.github/workflows/update-appcast.yml` | New — automates appcast on release |
| `gh-pages` branch: `appcast.xml` | New branch + file (see prerequisites in Section 3) |

## Out of Scope

- Delta/binary diffs (full DMG replacement only)
- Windows version (separate project)
- App Store distribution (uses Apple's own update mechanism)
- Notarization of XPC helpers (if notarization is added in future, each helper bundle must be individually code-signed with the same Developer ID identity as the main app before submission)
