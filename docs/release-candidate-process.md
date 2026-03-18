# Release Candidate Process

This document captures the maintainer workflow for cutting a signed and notarized macOS release candidate.

## Prerequisites

- A `Developer ID Application` certificate installed in Keychain
- A `notarytool` keychain profile configured for the Apple team
- Working `gh` authentication for publishing the GitHub prerelease

## Set Up notarytool

1. Create an app-specific password for your Apple ID at `https://appleid.apple.com/`.
2. Store the notary credentials in your login keychain:

```bash
xcrun notarytool store-credentials pibar-notary \
  --apple-id "you@example.com" \
  --team-id "GB7Z2TZ8LT" \
  --password "app-specific-password"
```

## Build The Release Candidate

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `PiBar.xcodeproj/project.pbxproj`.
2. Build the signed and notarized DMG:

```bash
scripts/build-release-dmg.sh \
  --artifact-name PiBar-<version>-rc<rc>-macOS \
  --sign-identity 'Developer ID Application: Matthew Smith (GB7Z2TZ8LT)' \
  --notary-profile pibar-notary
```

What the DMG workflow does:

- builds the app
- strips the build-only `LaunchAtLogin` resource bundle from the final app
- re-signs the embedded login helper with release entitlements
- re-signs the outer app with release entitlements
- builds a signed app ZIP
- notarizes and staples the app
- creates a DMG from the stapled app
- signs, notarizes, and staples the DMG

## Verify The Artifact

1. Mount the DMG.
2. Drag `PiBar.app` to `/Applications`.
3. Launch the installed app locally.
4. Confirm Gatekeeper does not show an unsigned or damaged warning.

## Publish The Release Candidate

1. Commit the version and release workflow changes.
2. Tag the release candidate:

```bash
git tag -a macOS-v<version>-rc<rc> -m "macOS v<version> RC <rc>"
```

3. Push the commit and tag.
4. Create the GitHub prerelease and upload the DMG from `build/release/`.

Example asset name:

```text
PiBar-2.0-rc1-macOS.dmg
```
