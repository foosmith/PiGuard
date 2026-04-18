//
//  UpdateManager.swift
//  PiGuard
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.

#if !APPSTORE
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
#endif
