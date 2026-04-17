# In-App Updater Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Sparkle 2-powered "Check for Updates…" to PiGuard's macOS menu bar app, with a GitHub Actions workflow that auto-updates the appcast on every GitHub release.

**Architecture:** Sparkle 2.x is added via SPM. A thin `UpdateManager` singleton wraps `SPUStandardUpdaterController`. The appcast lives on a `gh-pages` branch; a GHA workflow signs the DMG and prepends a new appcast item on every release publish event.

**Tech Stack:** Swift/Cocoa, Sparkle 2.x (SPM), GitHub Actions (ubuntu-latest), Python 3 (appcast update script), GitHub Pages.

---

## Notes Before Starting

- **No unit test target exists** in this project. Each task ends with a build verification step instead of `xcodebuild test`. Manual smoke testing is covered in Task 9.
- **Tasks 1 and 2 require Xcode** open — they involve Xcode GUI operations (SPM package addition, XIB editing, Copy Files build phase). All other tasks are file edits.
- **Task 1 (key generation) must be completed before Task 3** (Info.plist requires the public key).
- The app lives in `mac/` inside the repo root. Open `mac/PiGuard.xcodeproj` in Xcode for all Xcode tasks.
- Existing SPM packages: HotKey (branch: main) and LaunchAtLogin-Legacy (branch: main).

---

## Task 1: Generate EdDSA Key Pair

**Files:**
- Modify: `mac/PiGuard/Info.plist` (public key added here — see Task 3)
- GitHub secret: `SPARKLE_PRIVATE_KEY` (added in GitHub repo settings)

> This task produces no committed code. It sets up the cryptographic key pair Sparkle uses to verify updates.

- [ ] **Step 1: Add Sparkle temporarily to resolve the package so you can run generate_keys**

  Skip ahead to Task 2 Step 1-2 to add the Sparkle package in Xcode. Then come back here. The `generate_keys` binary is at:
  ```
  ~/Library/Developer/Xcode/DerivedData/PiGuard-*/SourcePackages/checkouts/Sparkle/bin/generate_keys
  ```
  Or find it at:
  ```bash
  find ~/Library/Developer/Xcode/DerivedData -name "generate_keys" -path "*/Sparkle/*" 2>/dev/null | head -1
  ```

- [ ] **Step 2: Run generate_keys**

  ```bash
  $(find ~/Library/Developer/Xcode/DerivedData -name "generate_keys" -path "*/Sparkle/*" 2>/dev/null | head -1)
  ```

  Expected output (example — your values will differ):
  ```
  A public key was generated and saved to your keychain. Add the following to the SUPublicEDKey field in your Info.plist:

  aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890abcdefghijklmno=
  ```

  The private key is automatically saved to your macOS Keychain under the account name `ed25519`.

- [ ] **Step 3: Copy the public key**

  Save the printed base64 public key somewhere — you'll need it in Task 3.

- [ ] **Step 4: Export the private key for GitHub Actions**

  ```bash
  security find-generic-password -s "https://sparkle-project.org" -w
  ```

  This prints the base64 private key. Copy it.

- [ ] **Step 5: Add the private key to GitHub Actions secrets**

  Go to: `https://github.com/foosmith/PiGuard/settings/secrets/actions`

  Click **New repository secret**:
  - Name: `SPARKLE_PRIVATE_KEY`
  - Secret: paste the base64 private key from Step 4

  Click **Add secret**.

---

## Task 2: Add Sparkle via Xcode SPM + Configure XPC Helpers

**Files:**
- Modify: `mac/PiGuard.xcodeproj/project.pbxproj` (auto-updated by Xcode)
- Modify: `mac/PiGuard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (auto-updated by Xcode)

> All steps in this task are done in Xcode's GUI.

- [ ] **Step 1: Add the Sparkle package**

  In Xcode with `mac/PiGuard.xcodeproj` open:
  1. File → Add Package Dependencies…
  2. In the search box paste: `https://github.com/sparkle-project/Sparkle`
  3. Set **Dependency Rule** to **Up to Next Major Version**, enter `2.0.0`
  4. Click **Add Package**
  5. In the "Choose Package Products" sheet, check **Sparkle** and set the target to **PiGuard**
  6. Click **Add Package**

- [ ] **Step 2: Note the resolved Sparkle version**

  After Xcode finishes resolving, check Package.resolved:
  ```bash
  cat "mac/PiGuard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" | grep -A6 '"sparkle"'
  ```
  Note the `"version"` value (e.g. `"2.6.4"`). You'll need this in Task 11 Step 2.

- [ ] **Step 3: Add the XPC helper Copy Files build phase**

  In Xcode, select the **PiGuard** target → Build Phases tab:
  1. Click **+** → **New Copy Files Phase**
  2. Set **Destination** to **Wrapper**
  3. Leave the **Subpath** field empty
  4. Click **+** inside the phase → in the file picker, navigate to the Sparkle package in the project navigator → find and add `Sparkle Helper (Installer).app`
  5. Repeat to add `Sparkle Helper (UI).app`
  6. For each helper, tick the **Code Sign On Copy** checkbox in the phase row

  > If you cannot find the helpers in the file picker, they appear under **Products** inside the Sparkle package in the project navigator after the package has been added and the project has been built once.

- [ ] **Step 4: Build the project to verify Sparkle links correctly**

  In Xcode: Product → Build (⌘B).

  Expected: Build Succeeded. No missing symbol errors.

- [ ] **Step 5: Commit**

  ```bash
  cd mac
  git add PiGuard.xcodeproj
  git commit -m "feat: add Sparkle 2 via SPM"
  ```

---

## Task 3: Update Info.plist

**Files:**
- Modify: `mac/PiGuard/Info.plist`

- [ ] **Step 1: Add SUFeedURL and SUPublicEDKey**

  Open `mac/PiGuard/Info.plist` and add these two keys inside the root `<dict>`, before the closing `</dict>`:

  ```xml
  	<key>SUFeedURL</key>
  	<string>https://foosmith.github.io/PiGuard/appcast.xml</string>
  	<key>SUPublicEDKey</key>
  	<string>PASTE_YOUR_PUBLIC_KEY_HERE</string>
  ```

  Replace `PASTE_YOUR_PUBLIC_KEY_HERE` with the base64 public key from Task 1 Step 2.

- [ ] **Step 2: Build to verify plist is valid**

  ```bash
  cd mac
  xcodebuild -scheme PiGuard -configuration Debug build 2>&1 | tail -5
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add PiGuard/Info.plist
  git commit -m "feat: add Sparkle feed URL and public key to Info.plist"
  ```

---

## Task 4: Create UpdateManager.swift

**Files:**
- Create: `mac/PiGuard/Manager/UpdateManager.swift`

- [ ] **Step 1: Create the file**

  Create `mac/PiGuard/Manager/UpdateManager.swift` with the following content:

  ```swift
  //
  //  UpdateManager.swift
  //  PiGuard
  //
  //  This Source Code Form is subject to the terms of the Mozilla Public
  //  License, v. 2.0. If a copy of the MPL was not distributed with this
  //  file, You can obtain one at http://mozilla.org/MPL/2.0/.

  import Sparkle

  final class UpdateManager {
      static let shared = UpdateManager()

      private let updaterController: SPUStandardUpdaterController

      private init() {
          updaterController = SPUStandardUpdaterController(
              startingUpdater: true,
              updaterDelegate: nil,
              userDriverDelegate: nil
          )
      }

      /// User-initiated update check — shows Sparkle's update window.
      func checkForUpdates() {
          updaterController.checkForUpdates(nil)
      }

      /// Silent background check — used on launch when auto-check preference is on.
      /// Sparkle suppresses all UI if no update is found.
      func checkForUpdatesInBackground() {
          updaterController.updater.checkForUpdatesInBackground()
      }
  }
  ```

- [ ] **Step 2: Add the file to the Xcode target**

  In Xcode, right-click the `Manager` group in the project navigator → **Add Files to "PiGuard"…** → select `UpdateManager.swift` → ensure **PiGuard** target is checked → click **Add**.

- [ ] **Step 3: Build to verify it compiles**

  In Xcode: Product → Build (⌘B).

  Expected: Build Succeeded. If you see `No such module 'Sparkle'`, verify Sparkle was added to the PiGuard target in Task 2.

- [ ] **Step 4: Commit**

  ```bash
  git add PiGuard/Manager/UpdateManager.swift
  git commit -m "feat: add UpdateManager wrapping SPUStandardUpdaterController"
  ```

---

## Task 5: Update Preferences.swift

**Files:**
- Modify: `mac/PiGuard/Data Sources/Preferences.swift`

- [ ] **Step 1: Add the key constant**

  In `Preferences.swift`, inside `fileprivate enum Key` (around line 41, after `hideMenuBarIcon`), add:

  ```swift
          static let automaticallyCheckForUpdates = "SUEnableAutomaticChecks"
  ```

- [ ] **Step 2: Register the default value**

  In `Preferences.standard`, inside the `database.register(defaults:)` call (around line 72, after `Key.hideMenuBarIcon: false`), add:

  ```swift
              Key.automaticallyCheckForUpdates: false,
  ```

- [ ] **Step 3: Add the typed accessor and setter**

  In the `UserDefaults` extension, after the `hideMenuBarIcon` accessor block (around line 316), add:

  ```swift
      // MARK: - Updates

      var automaticallyCheckForUpdates: Bool { bool(forKey: Preferences.Key.automaticallyCheckForUpdates) }
      func set(automaticallyCheckForUpdates: Bool) { set(automaticallyCheckForUpdates, for: Preferences.Key.automaticallyCheckForUpdates) }
  ```

- [ ] **Step 4: Build to verify**

  ```bash
  cd mac
  xcodebuild -scheme PiGuard -configuration Debug build 2>&1 | tail -5
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

  ```bash
  git add PiGuard/Data\ Sources/Preferences.swift
  git commit -m "feat: add automaticallyCheckForUpdates preference (SUEnableAutomaticChecks)"
  ```

---

## Task 6: Update AppDelegate.swift

**Files:**
- Modify: `mac/PiGuard/AppDelegate.swift`

- [ ] **Step 1: Add the launch check**

  In `AppDelegate.swift`, update `applicationDidFinishLaunching` to add the auto-check call after the existing line:

  ```swift
      func applicationDidFinishLaunching(_: Notification) {
          // Remove legacy v1 plaintext token that may be sitting in UserDefaults
          UserDefaults.standard.removeObject(forKey: "token")

          if Preferences.standard.automaticallyCheckForUpdates {
              UpdateManager.shared.checkForUpdatesInBackground()
          }
      }
  ```

- [ ] **Step 2: Build to verify**

  ```bash
  cd mac
  xcodebuild -scheme PiGuard -configuration Debug build 2>&1 | tail -5
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add PiGuard/AppDelegate.swift
  git commit -m "feat: trigger background update check on launch if preference is enabled"
  ```

---

## Task 7: Add "Check for Updates…" Menu Item

**Files:**
- Modify: `mac/PiGuard/Views/Main Menu/MainMenu.xib` (via Xcode Interface Builder)
- Modify: `mac/PiGuard/Views/Main Menu/MainMenuController.swift`

- [ ] **Step 1: Add the menu item in Interface Builder**

  Open `MainMenu.xib` in Xcode. Find the status bar menu (the `NSMenu` connected to the `mainMenu` outlet):
  1. Locate the "About PiGuard" menu item near the bottom of the menu
  2. Drag a new **Menu Item** from the Object Library and drop it immediately below "About PiGuard"
  3. Set its **Title** to `Check for Updates…` (use the ellipsis character `…`, not three dots)
  4. Leave **Tag**, **Key Equivalent**, and **Action** empty for now — you'll connect the action in the next step

- [ ] **Step 2: Wire the outlet and action in MainMenuController.swift**

  In `MainMenuController.swift`, add the outlet in the `// MARK: - Outlets` section (around line 82, after `queryLogMenuItem`):

  ```swift
      @IBOutlet var checkForUpdatesMenuItem: NSMenuItem!
  ```

  Add the action in the `// MARK: - Actions` section (after `aboutAction`, around line 124):

  ```swift
      @IBAction func checkForUpdatesAction(_: NSMenuItem) {
          UpdateManager.shared.checkForUpdates()
      }
  ```

- [ ] **Step 3: Connect in Interface Builder**

  Back in `MainMenu.xib`:
  1. Control-drag from **MainMenuController** (in the document outline) to the new "Check for Updates…" menu item → connect to `checkForUpdatesMenuItem`
  2. Control-drag from the "Check for Updates…" menu item to **MainMenuController** → connect to `checkForUpdatesAction:`

- [ ] **Step 4: Build to verify**

  In Xcode: Product → Build (⌘B).

  Expected: Build Succeeded. No unresolved IBOutlet/IBAction warnings.

- [ ] **Step 5: Commit**

  ```bash
  git add "PiGuard/Views/Main Menu/MainMenu.xib" "PiGuard/Views/Main Menu/MainMenuController.swift"
  git commit -m "feat: add Check for Updates menu item"
  ```

---

## Task 8: Add Auto-Update Checkbox to Preferences

**Files:**
- Modify: `mac/PiGuard/Views/Preferences/PreferencesViewController.swift`

The `hideMenuBarIconCheckbox` is the exact pattern to follow — it is a programmatic `NSButton` inserted into the view hierarchy in `viewDidLoad`, read in `updateUI`, and saved in `saveSettings`.

- [ ] **Step 1: Add the checkbox property**

  In `PreferencesViewController.swift`, add this lazy property in the properties section, after `hideMenuBarIconCheckbox` (around line 73):

  ```swift
      private lazy var automaticallyCheckForUpdatesCheckbox: NSButton = {
          let cb = NSButton(checkboxWithTitle: "Automatically check for updates on launch", target: self, action: #selector(checkboxAction(_:)))
          return cb
      }()
  ```

- [ ] **Step 2: Insert the checkbox in viewDidLoad**

  In `viewDidLoad`, after the block that inserts `hideMenuBarIconCheckbox` (after line ~201, after the `NSLayoutConstraint.activate([...])` for `hideMenuBarIconCheckbox`):

  Find this constraint activation block:
  ```swift
              NSLayoutConstraint.activate([
                  hideMenuBarIconCheckbox.leadingAnchor.constraint(equalTo: shortcutEnabledCheckbox.leadingAnchor),
                  hideMenuBarIconCheckbox.topAnchor.constraint(equalTo: shortcutEnabledCheckbox.bottomAnchor, constant: 8),
                  launchAtLogincheckbox.topAnchor.constraint(equalTo: hideMenuBarIconCheckbox.bottomAnchor, constant: 8),
              ])
  ```

  Replace it with:
  ```swift
              NSLayoutConstraint.activate([
                  hideMenuBarIconCheckbox.leadingAnchor.constraint(equalTo: shortcutEnabledCheckbox.leadingAnchor),
                  hideMenuBarIconCheckbox.topAnchor.constraint(equalTo: shortcutEnabledCheckbox.bottomAnchor, constant: 8),
              ])

              automaticallyCheckForUpdatesCheckbox.translatesAutoresizingMaskIntoConstraints = false
              parent.addSubview(automaticallyCheckForUpdatesCheckbox)
              NSLayoutConstraint.activate([
                  automaticallyCheckForUpdatesCheckbox.leadingAnchor.constraint(equalTo: shortcutEnabledCheckbox.leadingAnchor),
                  automaticallyCheckForUpdatesCheckbox.topAnchor.constraint(equalTo: hideMenuBarIconCheckbox.bottomAnchor, constant: 8),
                  launchAtLogincheckbox.topAnchor.constraint(equalTo: automaticallyCheckForUpdatesCheckbox.bottomAnchor, constant: 8),
              ])
  ```

- [ ] **Step 3: Read the checkbox state in updateUI**

  In `updateUI`, after the line that sets `hideMenuBarIconCheckbox.state` (around line 222):

  ```swift
          automaticallyCheckForUpdatesCheckbox.state = Preferences.standard.automaticallyCheckForUpdates ? .on : .off
  ```

- [ ] **Step 4: Save the checkbox state in saveSettings**

  In `saveSettings`, after the line that saves `hideMenuBarIcon` (around line 272):

  ```swift
          Preferences.standard.set(automaticallyCheckForUpdates: automaticallyCheckForUpdatesCheckbox.state == .on)
  ```

- [ ] **Step 5: Build to verify**

  ```bash
  cd mac
  xcodebuild -scheme PiGuard -configuration Debug build 2>&1 | tail -5
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

  ```bash
  git add "PiGuard/Views/Preferences/PreferencesViewController.swift"
  git commit -m "feat: add auto-check for updates checkbox to Preferences"
  ```

---

## Task 9: Manual Smoke Test

> This task has no code changes. Verify the app works end-to-end before touching CI.

- [ ] **Step 1: Run the app in Xcode**

  In Xcode: Product → Run (⌘R). PiGuard should appear in the menu bar.

- [ ] **Step 2: Verify "Check for Updates…" appears**

  Right-click (or left-click) the PiGuard menu bar icon. Verify "Check for Updates…" is visible in the menu.

- [ ] **Step 3: Trigger a check**

  Click "Check for Updates…". Sparkle should show either:
  - An update dialog (if the appcast URL resolves and has a newer version)
  - "You're up to date!" (if the appcast is empty/absent — expected at this stage since gh-pages isn't set up yet)
  - A network error alert — acceptable; it just means the appcast URL doesn't resolve yet

  **Not acceptable:** a crash or a hang.

- [ ] **Step 4: Verify Preferences checkbox**

  Open Preferences (from the menu). Verify "Automatically check for updates on launch" checkbox appears and persists its state between opens.

- [ ] **Step 5: Commit nothing** (smoke test produces no changes)

---

## Task 10: Bootstrap GitHub Pages + Appcast Skeleton

> This task creates the `gh-pages` branch and commits the initial `appcast.xml` skeleton. The GHA workflow depends on this file existing.

- [ ] **Step 1: Create the gh-pages branch**

  Run from the repo root (not `mac/`):

  ```bash
  git checkout --orphan gh-pages
  git reset --hard
  git commit --allow-empty -m "chore: init gh-pages branch"
  git push origin gh-pages
  git checkout master
  ```

- [ ] **Step 2: Commit the appcast skeleton**

  ```bash
  git checkout gh-pages
  ```

  Create `appcast.xml` at the repo root with this content:

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

  ```bash
  git add appcast.xml
  git commit -m "chore: add initial appcast.xml skeleton"
  git push origin gh-pages
  git checkout master
  ```

- [ ] **Step 3: Enable GitHub Pages**

  Go to: `https://github.com/foosmith/PiGuard/settings/pages`

  - Source: **Deploy from a branch**
  - Branch: `gh-pages` / `/ (root)`
  - Click **Save**

  After a minute, verify `https://foosmith.github.io/PiGuard/appcast.xml` returns the skeleton XML.

---

## Task 11: Create GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/update-appcast.yml`
- Create: `.github/scripts/update_appcast.py`

> This task creates two files on `master`. The workflow is triggered only when a GitHub release is published — it does not affect normal development builds.
>
> **Build number convention:** PiGuard DMG filenames follow `PiGuard-{SHORT_VERSION}-{BUILD_NUMBER}-macOS.dmg` (e.g. `PiGuard-3.4-702-macOS.dmg`). The workflow extracts `SHORT_VERSION` (marketing version, for `<sparkle:shortVersionString>`) and `BUILD_NUMBER` (for `<sparkle:version>`) directly from the DMG filename.

- [ ] **Step 1: Create the .github directory structure**

  ```bash
  mkdir -p .github/workflows .github/scripts
  ```

- [ ] **Step 2: Set the Sparkle version env var**

  From Task 2 Step 2, note the Sparkle version in `Package.resolved`. Use that version in the workflow below (replace `2.x.y`).

- [ ] **Step 3: Create the Python appcast update script**

  Create `.github/scripts/update_appcast.py`:

  ```python
  #!/usr/bin/env python3
  """Prepend a new <item> to appcast.xml for a Sparkle release.

  Usage:
      python3 update_appcast.py \\
          --appcast appcast.xml \\
          --title "PiGuard 3.4" \\
          --version 702 \\
          --short-version 3.4 \\
          --pub-date 2026-04-17T12:00:00Z \\
          --dmg-url https://github.com/.../PiGuard-3.4-702-macOS.dmg \\
          --dmg-length 12345678 \\
          --signature "base64sig==" \\
          --release-notes-file release_body.txt
  """

  import argparse
  from email.utils import formatdate
  from datetime import datetime


  def markdown_to_html(md_text: str) -> str:
      try:
          import markdown
          return markdown.markdown(md_text)
      except ImportError:
          escaped = md_text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
          return f"<pre>{escaped}</pre>"


  def build_item(
      title: str,
      version: str,
      short_version: str,
      pub_date_rfc: str,
      dmg_url: str,
      dmg_length: str,
      signature: str,
      min_os: str,
      release_notes_html: str,
  ) -> str:
      return (
          f"    <item>\n"
          f"        <title>{title}</title>\n"
          f"        <pubDate>{pub_date_rfc}</pubDate>\n"
          f"        <sparkle:version>{version}</sparkle:version>\n"
          f"        <sparkle:shortVersionString>{short_version}</sparkle:shortVersionString>\n"
          f"        <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>\n"
          f"        <enclosure\n"
          f"            url=\"{dmg_url}\"\n"
          f"            length=\"{dmg_length}\"\n"
          f"            type=\"application/octet-stream\"\n"
          f"            sparkle:edSignature=\"{signature}\" />\n"
          f"        <description><![CDATA[{release_notes_html}]]></description>\n"
          f"    </item>"
      )


  def main():
      parser = argparse.ArgumentParser(description=__doc__)
      parser.add_argument("--appcast", required=True)
      parser.add_argument("--title", required=True)
      parser.add_argument("--version", required=True, help="CFBundleVersion (build number)")
      parser.add_argument("--short-version", required=True, help="CFBundleShortVersionString (marketing version)")
      parser.add_argument("--pub-date", required=True, help="ISO 8601 date from GitHub API")
      parser.add_argument("--dmg-url", required=True)
      parser.add_argument("--dmg-length", required=True)
      parser.add_argument("--signature", required=True, help="EdDSA signature from sign_update -p")
      parser.add_argument("--min-os", default="11.0")
      parser.add_argument("--release-notes-file", required=True, help="Path to file containing Markdown release notes")
      args = parser.parse_args()

      dt = datetime.fromisoformat(args.pub_date.replace("Z", "+00:00"))
      pub_date_rfc = formatdate(dt.timestamp(), usegmt=True)

      with open(args.release_notes_file, encoding="utf-8") as f:
          notes_html = markdown_to_html(f.read())

      item_xml = build_item(
          title=args.title,
          version=args.version,
          short_version=args.short_version,
          pub_date_rfc=pub_date_rfc,
          dmg_url=args.dmg_url,
          dmg_length=args.dmg_length,
          signature=args.signature,
          min_os=args.min_os,
          release_notes_html=notes_html,
      )

      with open(args.appcast, encoding="utf-8") as f:
          content = f.read()

      if "<item>" in content:
          new_content = content.replace("<item>", item_xml + "\n    <item>", 1)
      else:
          new_content = content.replace("</channel>", item_xml + "\n    </channel>")

      with open(args.appcast, "w", encoding="utf-8") as f:
          f.write(new_content)

      print(f"Prepended item for {args.short_version} (build {args.version}) to {args.appcast}")


  if __name__ == "__main__":
      main()
  ```

- [ ] **Step 4: Create the workflow file**

  Create `.github/workflows/update-appcast.yml`:

  ```yaml
  name: Update Appcast

  on:
    release:
      types: [published]

  permissions:
    contents: write

  env:
    SPARKLE_VERSION: "2.x.y"  # Keep in sync with Package.resolved

  jobs:
    update-appcast:
      runs-on: ubuntu-latest

      steps:
        - name: Download Sparkle tools
          run: |
            curl -L "https://github.com/sparkle-project/Sparkle/releases/download/${{ env.SPARKLE_VERSION }}/Sparkle-${{ env.SPARKLE_VERSION }}.tar.bz2" -o sparkle.tar.bz2
            mkdir sparkle-tools
            tar -xjf sparkle.tar.bz2 -C sparkle-tools
            chmod +x sparkle-tools/bin/sign_update

        - name: Checkout gh-pages
          uses: actions/checkout@v4
          with:
            ref: gh-pages

        - name: Checkout master scripts
          uses: actions/checkout@v4
          with:
            ref: master
            path: master-src
            sparse-checkout: .github/scripts

        - name: Download release DMG
          env:
            GH_TOKEN: ${{ github.token }}
          run: |
            gh release download "${{ github.event.release.tag_name }}" \
              --repo "${{ github.repository }}" \
              --pattern "*.dmg"
            DMG_FILE=$(ls *.dmg | head -1)
            echo "DMG_FILE=$DMG_FILE" >> $GITHUB_ENV

        - name: Extract version info from DMG filename
          run: |
            # DMG filename convention: PiGuard-{SHORT_VERSION}-{BUILD_NUMBER}-macOS.dmg
            # e.g. PiGuard-3.4-702-macOS.dmg -> SHORT_VERSION=3.4, BUILD_NUMBER=702
            SHORT_VERSION=$(echo "$DMG_FILE" | sed 's/PiGuard-\([^-]*\)-.*/\1/')
            BUILD_NUMBER=$(echo "$DMG_FILE" | sed 's/PiGuard-[^-]*-\([^-]*\)-.*/\1/')
            echo "SHORT_VERSION=$SHORT_VERSION" >> $GITHUB_ENV
            echo "BUILD_NUMBER=$BUILD_NUMBER" >> $GITHUB_ENV

        - name: Sign DMG
          env:
            SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
          run: |
            SIGNATURE=$(echo "$SPARKLE_PRIVATE_KEY" | ./sparkle-tools/bin/sign_update "$DMG_FILE" --ed-key-file - -p)
            echo "SIGNATURE=$SIGNATURE" >> $GITHUB_ENV

        - name: Get DMG file size
          run: |
            DMG_LENGTH=$(stat -c%s "$DMG_FILE")
            echo "DMG_LENGTH=$DMG_LENGTH" >> $GITHUB_ENV

        - name: Get release metadata
          env:
            GH_TOKEN: ${{ github.token }}
          run: |
            gh release view "${{ github.event.release.tag_name }}" \
              --repo "${{ github.repository }}" \
              --json name,body,publishedAt > release_meta.json

            python3 -c "
  import json
  d = json.load(open('release_meta.json'))
  open('RELEASE_NAME.txt', 'w').write(d['name'])
  open('release_body.txt', 'w').write(d['body'])
  open('PUB_DATE.txt', 'w').write(d['publishedAt'])
  "
            echo "RELEASE_NAME=$(cat RELEASE_NAME.txt)" >> $GITHUB_ENV
            echo "PUB_DATE=$(cat PUB_DATE.txt)" >> $GITHUB_ENV

        - name: Install markdown Python package
          run: pip install markdown

        - name: Update appcast
          run: |
            DMG_URL="https://github.com/${{ github.repository }}/releases/download/${{ github.event.release.tag_name }}/$DMG_FILE"

            python3 master-src/.github/scripts/update_appcast.py \
              --appcast appcast.xml \
              --title "$RELEASE_NAME" \
              --version "$BUILD_NUMBER" \
              --short-version "$SHORT_VERSION" \
              --pub-date "$PUB_DATE" \
              --dmg-url "$DMG_URL" \
              --dmg-length "$DMG_LENGTH" \
              --signature "$SIGNATURE" \
              --release-notes-file release_body.txt

        - name: Commit and push appcast
          run: |
            git config user.name "github-actions[bot]"
            git config user.email "github-actions[bot]@users.noreply.github.com"
            git add appcast.xml
            git commit -m "chore: update appcast for ${{ github.event.release.tag_name }}"
            git push origin gh-pages
  ```

- [ ] **Step 5: Verify YAML syntax**

  ```bash
  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/update-appcast.yml'))" && echo "YAML valid"
  ```

  Expected: `YAML valid`

- [ ] **Step 6: Commit**

  ```bash
  git add .github/
  git commit -m "feat: add GitHub Actions workflow to auto-update appcast on release"
  ```

---

## Task 12: End-to-End Verification

> Verify the GHA workflow works by publishing a test release, or by reviewing the workflow logic manually.

- [ ] **Step 1: Verify the workflow triggers correctly (dry run)**

  Push to master and confirm the workflow only appears under "Actions" but does NOT run (it only triggers on `release: published`):

  ```bash
  git push origin master
  ```

  Go to `https://github.com/foosmith/PiGuard/actions` — the workflow should not have triggered.

- [ ] **Step 2: Review the SPARKLE_VERSION env var**

  Confirm `.github/workflows/update-appcast.yml` has the correct Sparkle version from `Package.resolved`:

  ```bash
  cat "mac/PiGuard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" | python3 -c "import json,sys; d=json.load(sys.stdin); [print(p['state'].get('version','(branch)')) for p in d['pins'] if 'sparkle' in p['identity']]"
  ```

  Compare with the `SPARKLE_VERSION` in the workflow. If they differ, update the workflow and commit.

- [ ] **Step 3: Confirm appcast is live**

  ```bash
  curl -s https://foosmith.github.io/PiGuard/appcast.xml
  ```

  Expected: the skeleton XML from Task 10.

- [ ] **Step 4: Final push**

  If any fixes were made in this task:

  ```bash
  git add .github/workflows/update-appcast.yml
  git commit -m "fix: correct Sparkle version in appcast workflow"
  git push origin master
  ```
