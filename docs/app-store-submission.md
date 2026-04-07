# App Store Submission Draft

This document is a working draft for the first macOS App Store submission of PiGuard.

## Release

- App name: `PiGuard`
- Bundle ID: `com.foosmith.PiGuard`
- Version: `2.3`
- Build: `696`
- Category: `Utilities`

## App Store Metadata

### Subtitle

```text
Pi-hole & AdGuard Control
```

### Promotional Text

```text
Control Pi-hole and AdGuard Home from your Mac menu bar, with mixed-backend monitoring, query visibility, and Pi-hole v6 sync tools.
```

### Description

```text
PiGuard is a native macOS menu bar utility for monitoring and controlling DNS filtering servers without living in a browser tab.

Designed for home labs and self-hosted networks, PiGuard gives you a fast control point for daily status checks and common actions across modern DNS filtering setups.

With PiGuard, you can:

- Monitor Pi-hole v5 servers
- Monitor Pi-hole v6 servers
- Monitor AdGuard Home servers
- Manage mixed-backend environments in one app session
- Enable or disable blocking from the menu bar
- Trigger gravity and filter refresh actions
- Review recent query log activity
- View top blocked domains and top clients
- Configure launch at login and keyboard shortcuts
- Run primary-to-secondary sync workflows for Pi-hole v6

PiGuard is intended for people who already run Pi-hole or AdGuard Home and want a lightweight native macOS control center for those servers.

Pi-hole is a registered trademark of Pi-hole LLC.
AdGuard is a registered trademark of AdGuard Software Ltd.
PiGuard is independent and is not affiliated with either company.
```

### Keywords

```text
pihole,pi-hole,adguard,dns,network,menu bar,homelab,server,privacy,utilities
```

### Support URL

```text
https://github.com/foosmith/PiGuard
```

### Marketing URL

```text
https://github.com/foosmith/PiGuard
```

### Privacy Policy URL

Publish the privacy policy at a stable public URL before submission. Suggested source file:

```text
docs/privacy-policy.md
```

Suggested public URL:

```text
https://github.com/foosmith/PiGuard/blob/master/docs/privacy-policy.md
```

## App Privacy Answers

Apple App Privacy recommendation for the current PiGuard codebase:

```text
No, we do not collect data from this app.
```

Reasoning:

- PiGuard connects directly to user-configured Pi-hole and AdGuard Home servers
- The app does not send analytics, tracking, crash reporting, or advertising data to a PiGuard-operated backend
- Optional logging stays local on the user’s Mac
- Preferences are stored locally on device

Caveat:

- This is the correct App Store Connect answer only as long as the app continues to avoid developer-hosted analytics, crash reporting, ads, or remote logging
- Credentials are still stored locally in app preferences, which is a security concern but not by itself an App Privacy collection category

## Privacy Manifest

This repo currently does not contain a local `PrivacyInfo.xcprivacy` file.

Before upload, verify in Xcode Organizer or App Store Connect whether a privacy manifest is required for this app or any embedded dependency in the final archive. If Organizer flags it, add one before submission.

## Review Notes

```text
PiGuard is a menu bar utility. After launch, it appears in the macOS menu bar and does not display a Dock icon.

For App Review, please use this dedicated review-only Pi-hole server:

Server type: Pi-hole
Host: dns.sidious.net
Port: 443
Protocol: HTTPS
Username: not required
Password: N2w3soBStx6nJAga41u9

Validation steps:
1. Launch PiGuard.
2. Open Preferences from the menu bar.
3. Add a new server with the review credentials above.
4. Use Test Connection.
5. Save the server.
6. Verify the server status appears in the menu bar.
7. Disable blocking.
8. Re-enable blocking.
9. Trigger refresh.
10. Open Query Log.

Notes:
- The review server is a dedicated temporary environment for App Review only.
- Accessing https://dns.sidious.net redirects to the Pi-hole admin interface.
- PiGuard is a menu bar app, so its primary UI is in the macOS menu bar rather than a standard window at launch.
```

## Review Demo Environment

This review server is intentionally separate from the private home-lab environment.

```text
Review server type: Pi-hole
Review host: dns.sidious.net
Review port: 443
Review protocol: HTTPS
Review username: not required
Review password or app password: N2w3soBStx6nJAga41u9
```

Operational notes:

- This is a dedicated review-only Pi-hole instance
- The public review entrypoint is `https://dns.sidious.net`
- The reverse proxy redirects `/` to `/admin/`
- The backing Docker service is isolated from the production Pi-hole setup

## Screenshots To Prepare

Recommended macOS screenshot set:

- Menu bar with live status visible
- Preferences window showing multi-backend server setup
- Query Log window
- Sync Settings window
- Top blocked and top clients menus

## Submission Checklist

- Confirm App Store Connect app record exists for `com.foosmith.PiGuard`
- Upload App Store build from Xcode Organizer, not the GitHub DMG
- Add App Privacy answers in App Store Connect
- Add screenshots and app icon metadata
- Add support and marketing URLs
- Paste review notes
- Paste review server credentials
- Confirm no user-facing text still says `Beta`
- Confirm release build launches correctly after install

## Upload Flow

Use Xcode Organizer for the Mac App Store build upload. Do not upload the GitHub DMG.

1. Open `PiGuard.xcodeproj` in Xcode.
2. Select the `PiGuard` scheme.
3. Change the build destination to `Any Mac (Apple Silicon, Intel)`.
4. Choose `Product` -> `Archive`.
5. Wait for the archive to appear in Organizer.
6. In Organizer, select the new archive for version `2.3` build `696`.
7. Click `Distribute App`.
8. Choose `App Store Connect`.
9. Choose `Upload`.
10. Keep automatic symbol handling enabled unless you have a reason not to.
11. Complete signing checks and upload the build.
12. In App Store Connect, wait for the build to finish processing.
13. Open the app record and attach build `696` to version `2.3`.
14. Fill in metadata, App Privacy, screenshots, and review information.
15. Submit for review.

## App Store Connect Entry Checklist

- App name: `PiGuard`
- Platform: `macOS`
- Bundle ID: `com.foosmith.PiGuard`
- SKU: choose a stable internal identifier such as `piguard-macos`
- Category: `Utilities`
- Privacy policy URL: required
- Support URL: required
- Review contact information: required
- Review notes: required for this app because it is menu-bar-only and depends on external servers

## Repo-Specific Risks Before Submission

- Credentials are still stored in app preferences rather than moved fully to Keychain
- App Review will need a working external server to evaluate the app properly
- Because the app is menu-bar-only, the review note is important to avoid confusion during launch testing
