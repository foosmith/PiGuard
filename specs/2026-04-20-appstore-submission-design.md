# App Store Submission Design

**Date:** 2026-04-20
**Status:** Approved

## Overview

Prepare PiGuard for dual distribution: direct download (GitHub/DMG with Sparkle auto-update) and Mac App Store. The app already has sandbox, hardened runtime, and `#if !APPSTORE` guards in place. Three gaps need to close: the build configuration does not properly separate App Store from direct-download builds, Sparkle is still embedded in every build regardless of the compilation guards, and a `PrivacyInfo.xcprivacy` is missing.

## Section 1: Build Configuration Split

A new "AppStore" Xcode build configuration is added to the project, duplicated from Release. The `SWIFT_ACTIVE_COMPILATION_CONDITIONS[arch=*] = APPSTORE` setting, which currently lives in Release, is moved into the new AppStore configuration. Release is restored to clean standard Release settings so direct-download DMG builds compile Sparkle back in.

A new "PiGuard AppStore" Xcode scheme is created. Its Archive action targets the AppStore configuration and uses automatic code signing with the Distribution certificate. The existing "PiGuard" scheme (Release/Debug) is left unchanged.

**Files changed:**
- `mac/PiGuard.xcodeproj/project.pbxproj` — add AppStore configuration entry, move APPSTORE flag
- `mac/PiGuard.xcodeproj/xcshareddata/xcschemes/PiGuard AppStore.xcscheme` — new scheme file

## Section 2: Sparkle Strip Script

A new "Run Script" build phase is added to the PiGuard target, ordered after the "Embed Frameworks" phase. When `$CONFIGURATION` is `AppStore`, it removes Sparkle and its XPC helpers from the built bundle:

```bash
if [ "$CONFIGURATION" = "AppStore" ]; then
    rm -rf "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Frameworks/Sparkle.framework"
    rm -rf "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/XPCServices"
fi
```

The script is a no-op for Release and Debug builds. This ensures App Store Connect does not encounter Sparkle when scanning the uploaded binary.

**Files changed:**
- `mac/PiGuard.xcodeproj/project.pbxproj` — new PBXShellScriptBuildPhase entry, added to target's buildPhases list

## Section 3: PrivacyInfo.xcprivacy

A `PrivacyInfo.xcprivacy` file is added to the PiGuard target. Required since May 2024 for all Mac App Store submissions.

Declared API reasons:

| API category | Reason code | Justification |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | App reads and writes its own preferences via `UserDefaults.standard` |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` | `NSFileManager` use in the logging subsystem may access file timestamps |

`NSPrivacyTracking` is `false`. `NSPrivacyCollectedDataTypes` is empty (no user data collected or shared).

**Files changed:**
- `mac/PiGuard/PrivacyInfo.xcprivacy` — new file
- `mac/PiGuard.xcodeproj/project.pbxproj` — file reference and build file added to target's Copy Bundle Resources phase

## Out of Scope

The following are required for App Store Connect submission but are outside the scope of this code change and must be completed manually:

- App Store Connect listing: description, keywords, support URL, marketing URL
- Screenshots (1280×800 or 1440×900 for macOS)
- Archiving and uploading the build via Xcode Organizer using the "PiGuard AppStore" scheme
- Submitting for review in App Store Connect
