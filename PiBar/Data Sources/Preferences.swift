//
//  Preferences.swift
//  PiBar
//
//  Created by Brad Root on 5/17/20.
//  Copyright © 2020 Brad Root. All rights reserved.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation

struct Preferences {
    fileprivate enum Key {
        static let piholes = "piholes" // Deprecated in PiBar 1.1
        static let piholesV2 = "piholesV2" // Deprecated in PiBar 1.2
        static let piholesV3 = "piholesV3" // Deprecated in PiGuard draft
        static let piholesV4 = "piholesV4"
        static let showBlocked = "showBlocked"
        static let showQueries = "showQueries"
        static let showPercentage = "showPercentage"
        static let showLabels = "showLabels"
        static let verboseLabels = "verboseLabels"
        static let shortcutEnabled = "shortcutEnabled"
        static let pollingRate = "pollingRate"
        static let syncEnabled = "syncEnabled"
        static let syncPrimaryIdentifier = "syncPrimaryIdentifier"
        static let syncSecondaryIdentifier = "syncSecondaryIdentifier"
        static let syncIntervalMinutes = "syncIntervalMinutes"
        static let syncSkipGroups = "syncSkipGroups"
        static let syncSkipAdlists = "syncSkipAdlists"
        static let syncSkipDomains = "syncSkipDomains"
        static let syncDryRunEnabled = "syncDryRunEnabled"
        static let syncWipeSecondaryBeforeSync = "syncWipeSecondaryBeforeSync"
        static let syncLastRunAt = "syncLastRunAt"
        static let syncLastStatus = "syncLastStatus"
        static let syncLastMessage = "syncLastMessage"
        static let enableLogging = "enableLogging"
    }

    static var standard: UserDefaults {
        let database = UserDefaults.standard
        database.register(defaults: [
            Key.piholes: [],
            Key.piholesV2: [],
            Key.piholesV3: [],
            Key.piholesV4: [],
            Key.showBlocked: true,
            Key.showQueries: true,
            Key.showPercentage: true,
            Key.showLabels: false,
            Key.verboseLabels: false,
            Key.shortcutEnabled: true,
            Key.pollingRate: 3,
            Key.syncEnabled: false,
            Key.syncPrimaryIdentifier: "",
            Key.syncSecondaryIdentifier: "",
            Key.syncIntervalMinutes: 15,
            Key.syncSkipGroups: false,
            Key.syncSkipAdlists: false,
            Key.syncSkipDomains: false,
            Key.syncDryRunEnabled: false,
            Key.syncWipeSecondaryBeforeSync: false,
            Key.syncLastStatus: "",
            Key.syncLastMessage: "",
            Key.enableLogging: false,
        ])

        return database
    }
}

extension UserDefaults {
    var piholes: [PiholeConnectionV4] {
        if let array = array(forKey: Preferences.Key.piholesV2), !array.isEmpty {
            // Migrate from PiBar v1.1 format to PiBar v1.2 format if needed
            Log.debug("Found V1 Pi-holes")
            var piholesV2: [PiholeConnectionV2] = []
            var piholesV4: [PiholeConnectionV4] = []
            for data in array {
                Log.debug("Loading Pi-hole V2...")
                guard let data = data as? Data, let piholeConnection = PiholeConnectionV2(data: data) else { continue }
                piholesV2.append(piholeConnection)
            }
            if !piholesV2.isEmpty {
                for pihole in piholesV2 {
                    Log.debug("Converting V2 Pi-hole to V4")
                    piholesV4.append(PiholeConnectionV4(hostname: pihole.hostname, port: pihole.port, useSSL: pihole.useSSL, token: pihole.token, username: "", passwordProtected: pihole.passwordProtected, adminPanelURL: pihole.adminPanelURL, backendType: .piholeV5))
                }
                set([], for: Preferences.Key.piholesV2)
                let encodedArray = piholesV4.map { $0.encode()! }
                set(encodedArray, for: Preferences.Key.piholesV4)
            }
            return piholesV4
        } else if let array = array(forKey: Preferences.Key.piholesV3), !array.isEmpty {
            var piholesV4: [PiholeConnectionV4] = []
            for data in array {
                Log.debug("Loading V3 Pi-hole")
                guard let data = data as? Data, let piholeConnection = PiholeConnectionV3(data: data) else { continue }
                piholesV4.append(PiholeConnectionV4(piholeConnection))
            }
            if !piholesV4.isEmpty {
                set([], for: Preferences.Key.piholesV3)
                let encodedArray = piholesV4.map { $0.encode()! }
                set(encodedArray, for: Preferences.Key.piholesV4)
            }
            return piholesV4
        } else if let array = array(forKey: Preferences.Key.piholesV4), !array.isEmpty {
            var piholesV4: [PiholeConnectionV4] = []
            for data in array {
                Log.debug("Loading V4 connection")
                guard let data = data as? Data, let piholeConnection = PiholeConnectionV4(data: data) else { continue }
                piholesV4.append(piholeConnection)
            }
            return piholesV4
        }
        return []
    }

    func set(piholes: [PiholeConnectionV4]) {
        let array = piholes.map { $0.encode()! }
        set(array, for: Preferences.Key.piholesV4)
    }

    var showBlocked: Bool {
        return bool(forKey: Preferences.Key.showBlocked)
    }

    func set(showBlocked: Bool) {
        set(showBlocked, for: Preferences.Key.showBlocked)
    }

    var showQueries: Bool {
        return bool(forKey: Preferences.Key.showQueries)
    }

    func set(showQueries: Bool) {
        set(showQueries, for: Preferences.Key.showQueries)
    }

    var showPercentage: Bool {
        return bool(forKey: Preferences.Key.showPercentage)
    }

    func set(showPercentage: Bool) {
        set(showPercentage, for: Preferences.Key.showPercentage)
    }

    var showLabels: Bool {
        return bool(forKey: Preferences.Key.showLabels)
    }

    func set(showLabels: Bool) {
        set(showLabels, for: Preferences.Key.showLabels)
    }

    var verboseLabels: Bool {
        return bool(forKey: Preferences.Key.verboseLabels)
    }

    func set(verboseLabels: Bool) {
        set(verboseLabels, for: Preferences.Key.verboseLabels)
    }

    var shortcutEnabled: Bool {
        return bool(forKey: Preferences.Key.shortcutEnabled)
    }

    func set(shortcutEnabled: Bool) {
        set(shortcutEnabled, for: Preferences.Key.shortcutEnabled)
    }

    var pollingRate: Int {
        let savedPollingRate = integer(forKey: Preferences.Key.pollingRate)
        if savedPollingRate >= 3 {
            return savedPollingRate
        }
        set(pollingRate: 3)
        return 3
    }

    func set(pollingRate: Int) {
        set(pollingRate, for: Preferences.Key.pollingRate)
    }

    // Helpers

    var showTitle: Bool {
        return showQueries || showBlocked || showPercentage
    }

    // MARK: - Sync

    var syncEnabled: Bool { bool(forKey: Preferences.Key.syncEnabled) }
    func set(syncEnabled: Bool) { set(syncEnabled, for: Preferences.Key.syncEnabled) }

    var syncPrimaryIdentifier: String { string(forKey: Preferences.Key.syncPrimaryIdentifier) ?? "" }
    func set(syncPrimaryIdentifier: String) { set(syncPrimaryIdentifier, for: Preferences.Key.syncPrimaryIdentifier) }

    var syncSecondaryIdentifier: String { string(forKey: Preferences.Key.syncSecondaryIdentifier) ?? "" }
    func set(syncSecondaryIdentifier: String) { set(syncSecondaryIdentifier, for: Preferences.Key.syncSecondaryIdentifier) }

    var syncIntervalMinutes: Int {
        let v = integer(forKey: Preferences.Key.syncIntervalMinutes)
        return v >= 1 ? v : 15
    }
    func set(syncIntervalMinutes: Int) { set(syncIntervalMinutes, for: Preferences.Key.syncIntervalMinutes) }

    var syncSkipGroups: Bool { bool(forKey: Preferences.Key.syncSkipGroups) }
    func set(syncSkipGroups: Bool) { set(syncSkipGroups, for: Preferences.Key.syncSkipGroups) }

    var syncSkipAdlists: Bool { bool(forKey: Preferences.Key.syncSkipAdlists) }
    func set(syncSkipAdlists: Bool) { set(syncSkipAdlists, for: Preferences.Key.syncSkipAdlists) }

    var syncSkipDomains: Bool { bool(forKey: Preferences.Key.syncSkipDomains) }
    func set(syncSkipDomains: Bool) { set(syncSkipDomains, for: Preferences.Key.syncSkipDomains) }

    var syncDryRunEnabled: Bool { bool(forKey: Preferences.Key.syncDryRunEnabled) }
    func set(syncDryRunEnabled: Bool) { set(syncDryRunEnabled, for: Preferences.Key.syncDryRunEnabled) }

    var syncWipeSecondaryBeforeSync: Bool { bool(forKey: Preferences.Key.syncWipeSecondaryBeforeSync) }
    func set(syncWipeSecondaryBeforeSync: Bool) { set(syncWipeSecondaryBeforeSync, for: Preferences.Key.syncWipeSecondaryBeforeSync) }

    var syncLastRunAt: Date? { object(forKey: Preferences.Key.syncLastRunAt) as? Date }
    func set(syncLastRunAt: Date) { set(syncLastRunAt, for: Preferences.Key.syncLastRunAt) }

    var syncLastStatus: String { string(forKey: Preferences.Key.syncLastStatus) ?? "" }
    func set(syncLastStatus: SyncStatus) { set(syncLastStatus.rawValue, for: Preferences.Key.syncLastStatus) }

    var syncLastMessage: String { string(forKey: Preferences.Key.syncLastMessage) ?? "" }
    func set(syncLastMessage: String) { set(syncLastMessage, for: Preferences.Key.syncLastMessage) }

    // MARK: - Logging

    var enableLogging: Bool { bool(forKey: Preferences.Key.enableLogging) }
    func set(enableLogging: Bool) { set(enableLogging, for: Preferences.Key.enableLogging) }
}

private extension UserDefaults {
    func set(_ object: Any?, for key: String) {
        set(object, forKey: key)
        synchronize()
    }
}
