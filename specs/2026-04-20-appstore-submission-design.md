# App Store Submission Design

**Date:** 2026-04-20
**Status:** Approved

## Overview

Prepare PiGuard for dual distribution: direct download (GitHub/DMG with Sparkle auto-update) and Mac App Store. The app already has sandbox, hardened runtime, and `#if !APPSTORE` guards in place.

**Pre-existing defect being corrected:** The current Release configuration has `SWIFT_ACTIVE_COMPILATION_CONDITIONS[arch=*] = APPSTORE` set, which means all current DMG builds already compile with Sparkle excluded — a bug. Fixing the build configuration split also fixes this.

Three gaps to close:
1. The build configuration does not properly separate App Store from direct-download builds (and the current Release config is broken for DMG as a result).
2. Sparkle is still embedded in every build regardless of the `#if !APPSTORE` compilation guards.
3. A `PrivacyInfo.xcprivacy` is missing.

## Section 1: Build Configuration Split

Two new Xcode build configurations are added: one at **project level** and one at **target level**, both named "AppStore".

**Project-level AppStore config** (duplicated from project-level Release, UUID `449395E12471ABD700FA0C34`):
- Move `SWIFT_ACTIVE_COMPILATION_CONDITIONS[arch=*] = APPSTORE` from project-level Release into this config. Remove from Release so direct-download DMG builds compile Sparkle back in.
- Set `MACOSX_DEPLOYMENT_TARGET = 11.0` (project-level Release has `10.12`).
- Set `DEVELOPMENT_TEAM = GB7Z2TZ8LT` (project-level Release has `2Y9M69QJKZ` — a different team ID; the AppStore config must explicitly override this).

**Target-level AppStore config** (duplicated from target-level Release, UUID `449395E42471ABD700FA0C34`):
- Set `ENABLE_USER_SCRIPT_SANDBOXING = NO` (matches target-level Release; required for the LaunchAtLogin `copy-helper-swiftpm.sh` build phase to run).
- `CODE_SIGN_STYLE = Automatic` and `DEVELOPMENT_TEAM = GB7Z2TZ8LT` are inherited from target-level Release. With Automatic signing, Xcode resolves the Distribution certificate at archive time.
- Remove **both** `CODE_SIGN_IDENTITY = "Apple Development"` **and** `"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development"` from the AppStore target config. If either key remains, Xcode will use the Development identity for macOS builds instead of letting Automatic signing select Distribution.

The single `PiGuard.entitlements` file (containing `com.apple.security.app-sandbox`, `com.apple.security.network.client`, and `com.apple.security.files.user-selected.read-only`) is used for both Release and AppStore configurations — no separate entitlements file is needed. Keychain access (`SecItemAdd`, `SecItemCopyMatching`, etc.) needs no additional entitlement under App Sandbox — the app's own default keychain access is granted automatically.

A new "PiGuard AppStore" Xcode scheme is created. Its Archive action targets the AppStore configuration. The existing "PiGuard" scheme (Release/Debug) is left unchanged.

**Files changed:**
- `mac/PiGuard.xcodeproj/project.pbxproj` — add project-level and target-level AppStore configuration entries; move APPSTORE flag from project-level Release; set MACOSX_DEPLOYMENT_TARGET=11.0 and DEVELOPMENT_TEAM=GB7Z2TZ8LT in project-level AppStore config; remove both CODE_SIGN_IDENTITY keys from target-level AppStore config; set ENABLE_USER_SCRIPT_SANDBOXING=NO in target-level AppStore config
- `mac/PiGuard.xcodeproj/xcshareddata/xcschemes/PiGuard AppStore.xcscheme` — new scheme file

**Notes on third-party dependencies:**
- **HotKey**: uses Carbon's `RegisterEventHotKey`, which works in App Sandbox without accessibility permissions. No change needed.
- **LaunchAtLogin-Legacy**: uses `SMAppService.mainApp` on macOS 13+ (App Store-compatible) and a bundled LoginItem helper on macOS 11–12. Apple accepts LoginItem helpers on the App Store when properly signed. The existing `copy-helper-swiftpm.sh` build phase handles signing the helper. No change needed.
- **Sparkle**: excluded via `#if !APPSTORE` guards and the strip script in Section 2.

## Section 2: Sparkle Strip Script

A new "Run Script" build phase is added to the PiGuard target as the **last build phase** — appended after the existing `CopyFiles` phase (UUID `52E46A512F92D6EC0013DD87`), which is currently last. Current build phase order: Sources → Frameworks → Resources → ShellScript → Embed Frameworks → CopyFiles → *(new strip script)*.

Frameworks are embedded by the `Embed Frameworks` phase. The strip script runs after all phases are complete, which is safe: `$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Frameworks/` already contains the embedded Sparkle.framework by the time the strip script runs.

```bash
if [ "$CONFIGURATION" = "AppStore" ]; then
    rm -rf "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Frameworks/Sparkle.framework"
fi
```

Removing `Sparkle.framework` is sufficient: in Sparkle 2.x all XPC services (`Downloader.xpc`, `Installer.xpc`) and the Autoupdate binary live inside the framework bundle itself. The script is a no-op for Release and Debug builds. This ensures App Store Connect does not encounter Sparkle when scanning the uploaded binary.

**Files changed:**
- `mac/PiGuard.xcodeproj/project.pbxproj` — new `PBXShellScriptBuildPhase` entry appended as the last item in the target's `buildPhases` array

## Section 3: PrivacyInfo.xcprivacy

A `PrivacyInfo.xcprivacy` file is added to the PiGuard target. Required since May 2024 for all Mac App Store submissions.

Declared API reasons:

| API category | Reason code | Justification |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | App reads and writes its own preferences via `UserDefaults.standard` |

`NSPrivacyTracking` is `false`. `NSPrivacyCollectedDataTypes` is empty (no user data collected or shared).

Omitted categories:
- `NSPrivacyAccessedAPICategoryFileTimestamp` — no code path calls file timestamp APIs (`attributesOfItem`, `contentModificationDateKey`, etc.) on files outside the app's sandbox container. Verified by source inspection.
- `NSPrivacyAccessedAPICategorySystemBootTime` — polling timers use `Timer`/`DispatchQueue`; no direct `mach_absolute_time` or `clock_gettime` calls found in app code.

Both can be added post-submission if Apple's static analysis flags them.

`SUFeedURL` and `SUPublicEDKey` remain in `Info.plist` for the AppStore build. Apple does not reject apps for including these keys.

**Notes on App Store review:**
- The app uses `NSAllowsLocalNetworking` in the ATS config to communicate with Pi-hole and AdGuard Home over HTTP on the local network. This is explicitly permitted under App Sandbox. Reviewers may ask; the response is that the app's core functionality requires local network access to user-hosted DNS management servers.

**Files changed:**
- `mac/PiGuard/PrivacyInfo.xcprivacy` — new file
- `mac/PiGuard.xcodeproj/project.pbxproj` — file reference and build file added to target's Copy Bundle Resources phase

## Out of Scope

The following are required for App Store Connect submission but are outside the scope of this code change and must be completed manually:

- App Store Connect listing: description, keywords, support URL, marketing URL
- Screenshots (1280×800 or 1440×900 for macOS)
- Archiving and uploading the build via Xcode Organizer using the "PiGuard AppStore" scheme
- Submitting for review in App Store Connect
