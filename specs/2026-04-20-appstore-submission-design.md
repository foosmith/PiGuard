# App Store Submission Design

**Date:** 2026-04-20
**Status:** Approved

## Overview

Prepare PiGuard for dual distribution: direct download (GitHub/DMG with Sparkle auto-update) and Mac App Store. The app already has sandbox, hardened runtime, and `#if !APPSTORE` guards in place. Three gaps need to close: the build configuration does not properly separate App Store from direct-download builds, Sparkle is still embedded in every build regardless of the compilation guards, and a `PrivacyInfo.xcprivacy` is missing.

## Section 1: Build Configuration Split

A new "AppStore" Xcode build configuration is added to the project, duplicated from the **target-level** Release configuration (UUID `449395E42471ABD700FA0C34`). The `SWIFT_ACTIVE_COMPILATION_CONDITIONS[arch=*] = APPSTORE` setting, which currently lives in Release, is moved into the new AppStore configuration. Release is restored to clean standard Release settings so direct-download DMG builds compile Sparkle back in.

Code signing for the AppStore configuration uses `CODE_SIGN_STYLE = Automatic` (inherited from Release). Xcode automatically selects a Distribution certificate when archiving with Automatic signing — explicitly setting `CODE_SIGN_IDENTITY` is not needed and would conflict with Automatic mode. The team ID `GB7Z2TZ8LT` is inherited from the target-level Release settings.

The single `PiGuard.entitlements` file (containing `com.apple.security.app-sandbox`, `com.apple.security.network.client`, and `com.apple.security.files.user-selected.read-only`) is used for both Release and AppStore configurations — no separate entitlements file is needed.

A new "PiGuard AppStore" Xcode scheme is created. Its Archive action targets the AppStore configuration. The existing "PiGuard" scheme (Release/Debug) is left unchanged.

**Files changed:**
- `mac/PiGuard.xcodeproj/project.pbxproj` — add AppStore configuration entry, move APPSTORE flag
- `mac/PiGuard.xcodeproj/xcshareddata/xcschemes/PiGuard AppStore.xcscheme` — new scheme file

**Notes on third-party dependencies:**
- **HotKey**: uses Carbon's `RegisterEventHotKey`, which works in App Sandbox without accessibility permissions. No change needed.
- **LaunchAtLogin-Legacy**: uses `SMAppService.mainApp` on macOS 13+ (App Store-compatible) and a bundled LoginItem helper on macOS 11–12. Apple accepts LoginItem helpers on the App Store when properly signed. The existing `copy-helper-swiftpm.sh` build phase handles signing the helper. No change needed.
- **Sparkle**: excluded via `#if !APPSTORE` guards and the strip script in Section 2.

## Section 2: Sparkle Strip Script

A new "Run Script" build phase is added to the PiGuard target as the **last build phase** (after the existing "Embed Frameworks" phase). When `$CONFIGURATION` is `AppStore`, it removes Sparkle from the built bundle:

```bash
if [ "$CONFIGURATION" = "AppStore" ]; then
    rm -rf "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Frameworks/Sparkle.framework"
fi
```

Removing `Sparkle.framework` is sufficient: in Sparkle 2.x all XPC services (`Downloader.xpc`, `Installer.xpc`) and the Autoupdate binary live inside the framework bundle itself. The script is a no-op for Release and Debug builds. This ensures App Store Connect does not encounter Sparkle when scanning the uploaded binary.

**Files changed:**
- `mac/PiGuard.xcodeproj/project.pbxproj` — new PBXShellScriptBuildPhase entry appended as the last item in the target's `buildPhases` list

## Section 3: PrivacyInfo.xcprivacy

A `PrivacyInfo.xcprivacy` file is added to the PiGuard target. Required since May 2024 for all Mac App Store submissions.

Declared API reasons:

| API category | Reason code | Justification |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | App reads and writes its own preferences via `UserDefaults.standard` |

`NSPrivacyTracking` is `false`. `NSPrivacyCollectedDataTypes` is empty (no user data collected or shared).

`NSPrivacyAccessedAPICategoryFileTimestamp` is omitted — no code path in the app's sandbox accesses file timestamps of files outside its container. It can be added post-submission if Apple's static analysis flags it.

`SUFeedURL` and `SUPublicEDKey` remain in `Info.plist` for the AppStore build. Apple does not reject apps for including these keys, and conditionally removing them is not worth the added complexity.

**Notes on App Store review:**
- The app uses `NSAllowsLocalNetworking` in the ATS config to communicate with Pi-hole and AdGuard Home over HTTP on the local network. This is explicitly permitted under App Sandbox and does not require an entitlement, but reviewers may ask about it. The standard response is that the app's core functionality requires local network access to user-hosted DNS management servers.

**Files changed:**
- `mac/PiGuard/PrivacyInfo.xcprivacy` — new file
- `mac/PiGuard.xcodeproj/project.pbxproj` — file reference and build file added to target's Copy Bundle Resources phase

## Out of Scope

The following are required for App Store Connect submission but are outside the scope of this code change and must be completed manually:

- App Store Connect listing: description, keywords, support URL, marketing URL
- Screenshots (1280×800 or 1440×900 for macOS)
- Archiving and uploading the build via Xcode Organizer using the "PiGuard AppStore" scheme
- Submitting for review in App Store Connect
