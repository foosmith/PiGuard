//
//  UpdateManager.swift
//  PiGuard
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.

#if !APPSTORE
import Sparkle
import Darwin

final class UpdateManager {
    static let shared = UpdateManager()

    private let updaterController: SPUStandardUpdaterController

    private init() {
        // Strip com.apple.quarantine from Sparkle's embedded tools before starting
        // the updater. When the app is first installed from a downloaded DMG every
        // file inherits the quarantine xattr, which causes launchd to refuse to exec
        // Autoupdate and Installer.xpc when Sparkle submits them via SMJobSubmit.
        Self.clearSparkleQuarantine()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    private static func clearSparkleQuarantine() {
        guard let sparkleBundle = Bundle(identifier: "org.sparkle-project.Sparkle") else { return }
        let frameworkURL = sparkleBundle.bundleURL
        removexattr(frameworkURL.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        guard let enumerator = FileManager.default.enumerator(
            at: frameworkURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for case let url as URL in enumerator {
            removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
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
#endif
