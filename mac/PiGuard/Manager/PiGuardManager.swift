//
//  PiGuardManager.swift
//  PiGuard
//
//  Created by Brad Root on 5/20/20.
//  Copyright © 2020 Brad Root. All rights reserved.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import WidgetKit

protocol PiGuardManagerDelegate: AnyObject {
    func updateNetwork(_ network: PiholeNetworkOverview)
}

class PiGuardManager: NSObject {
    private var piholes: [String: Pihole] = [:]

    private var networkOverview: PiholeNetworkOverview {
        didSet {
            delegate?.updateNetwork(networkOverview)
        }
    }

    private var timer: Timer?
    private var syncTimer: Timer?
    private var updateInterval: TimeInterval
    private let operationQueue: OperationQueue = OperationQueue()
    private let syncQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "com.foosmith.PiGuard.syncQueue"
        return q
    }()

    override init() {
        Log.useEmoji = true

        operationQueue.maxConcurrentOperationCount = 1

        updateInterval = TimeInterval(Preferences.standard.pollingRate)

        networkOverview = PiholeNetworkOverview(
            networkStatus: .initializing,
            canBeManaged: false,
            totalQueriesToday: 0,
            adsBlockedToday: 0,
            adsPercentageToday: 0.0,
            averageBlocklist: 0,
            piholes: [:]
        )
        super.init()

        applyLoggingPreference()

        delegate?.updateNetwork(networkOverview)

        loadConnections()
    }

    // MARK: - Public Variables and Functions

    weak var delegate: PiGuardManagerDelegate?

    func loadConnections() {
        createPiholes(Preferences.standard.piholes)
    }

    func updateGravityOnNetwork() {
        Log.debug("Manager: Update Gravity requested")
        NotificationCenter.default.post(name: .piGuardGravityBegan, object: nil)
        Task {
            defer {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .piGuardGravityEnded, object: nil)
                }
            }
            for pihole in piholes.values {
                do {
                    if let api6 = pihole.api6 {
                        try await api6.triggerGravityUpdate()
                        Log.debug("Manager: Gravity update triggered for \(pihole.identifier)")
                    } else if let apiAdguard = pihole.apiAdguard {
                        try await apiAdguard.refreshFilters()
                        Log.debug("Manager: Filter refresh triggered for \(pihole.identifier)")
                    }
                } catch {
                    Log.error("Manager: Failed to trigger filter refresh for \(pihole.identifier): \(error)")
                }
            }
        }
    }

    func applyLoggingPreference() {
        if Preferences.standard.enableLogging {
            Log.logLevel = .debug
            Log.startFileLogging()
        } else {
            Log.logLevel = .off
            Log.stopFileLogging()
        }
    }

    func setPollingRate(to seconds: Int) {
        let newPollingRate = TimeInterval(seconds)
        if newPollingRate != updateInterval {
            Log.debug("Changed polling rate to: \(seconds)")
            updateInterval = newPollingRate
            startTimer()
        }
    }

    func syncNow() {
        Log.debug("Manager: Sync Now requested")
        NotificationCenter.default.post(name: .piGuardSyncBegan, object: nil)
        let operation = SyncPrimarySecondaryOperation()
        operation.completionBlock = {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .piGuardSyncEnded, object: nil)
            }
        }
        syncQueue.addOperation(operation)
    }

    func restartSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil

        guard Preferences.standard.syncEnabled else {
            Log.debug("Manager: Sync disabled, no sync timer started")
            return
        }

        let intervalSeconds = TimeInterval(Preferences.standard.syncIntervalMinutes * 60)
        Log.debug("Manager: Starting sync timer with interval \(Preferences.standard.syncIntervalMinutes) minutes")
        let newTimer = Timer(timeInterval: intervalSeconds, target: self, selector: #selector(timedSync), userInfo: nil, repeats: true)
        newTimer.tolerance = 5.0
        RunLoop.main.add(newTimer, forMode: .common)
        syncTimer = newTimer
    }

    @objc private func timedSync() {
        guard Preferences.standard.syncEnabled else { return }
        Log.debug("Manager: Timed sync triggered")
        syncNow()
    }

    // Enable / Disable Pi-hole(s)

    func toggleNetwork() {
        if networkStatus() == .enabled || networkStatus() == .partiallyEnabled {
            disableNetwork()
        } else if networkStatus() == .disabled {
            enableNetwork()
        }
    }

    func disableNetwork(seconds: Int? = nil) {
        stopTimer()

        let completionOperation = BlockOperation {
            self.updatePiholes()
            self.startTimer()
        }
        piholes.values.forEach { pihole in
            let operation = ChangePiholeStatusOperation(pihole: pihole, status: .disable, seconds: seconds)
            completionOperation.addDependency(operation)
            operationQueue.addOperation(operation)
        }
        operationQueue.addOperation(completionOperation)
    }

    func enableNetwork() {
        stopTimer()

        let completionOperation = BlockOperation {
            self.updatePiholes()
            self.startTimer()
        }
        piholes.values.forEach { pihole in
            let operation = ChangePiholeStatusOperation(pihole: pihole, status: .enable)
            completionOperation.addDependency(operation)
            operationQueue.addOperation(operation)
        }
        operationQueue.addOperation(completionOperation)
    }

    // MARK: - Private Functions

    // MARK: Timer

    private func startTimer() {
        stopTimer()

        let newTimer = Timer(timeInterval: updateInterval, target: self, selector: #selector(updatePiholes), userInfo: nil, repeats: true)
        newTimer.tolerance = 0.2
        RunLoop.main.add(newTimer, forMode: .common)

        timer = newTimer

        Log.debug("Manager: Timer Started")
    }

    private func stopTimer() {
        if let existingTimer = timer {
            Log.debug("Manager: Timer Stopped")
            existingTimer.invalidate()
            timer = nil
        }
    }

    // MARK: Data Updates

    private func createNewNetwork() {
        networkOverview = PiholeNetworkOverview(
            networkStatus: .initializing,
            canBeManaged: false,
            totalQueriesToday: 0,
            adsBlockedToday: 0,
            adsPercentageToday: 0.0,
            averageBlocklist: 0,
            piholes: [:]
        )
    }

    private func createPiholes(_ connections: [PiholeConnectionV4]) {
        Log.debug("Manager: Updating Connections")

        stopTimer()
        piholes.removeAll()
        createNewNetwork()
        
        for connection in connections {
            Log.debug("Manager: Updating Connection: \(connection.hostname)")
            switch connection.backendType {
            case .piholeV6:
                let api = Pihole6API(connection: connection)
                piholes[api.identifier] = Pihole(
                    api: nil,
                    api6: api,
                    apiAdguard: nil,
                    identifier: api.identifier,
                    online: false,
                    summary: nil,
                    canBeManaged: nil,
                    enabled: nil,
                    backendType: .piholeV6
                )
            case .piholeV5:
                let api = PiholeAPI(connection: connection)
                piholes[api.identifier] = Pihole(
                    api: api,
                    api6: nil,
                    apiAdguard: nil,
                    identifier: api.identifier,
                    online: false,
                    summary: nil,
                    canBeManaged: nil,
                    enabled: nil,
                    backendType: .piholeV5
                )
            case .adguardHome:
                let api = AdGuardHomeAPI(connection: connection)
                piholes[api.identifier] = Pihole(
                    api: nil,
                    api6: nil,
                    apiAdguard: api,
                    identifier: api.identifier,
                    online: false,
                    summary: nil,
                    canBeManaged: nil,
                    enabled: nil,
                    backendType: .adguardHome
                )
            }
        }

        updatePiholes()

        startTimer()
    }

    @objc private func updatePiholes() {
        Log.debug("Manager: Updating Pi-holes")

        var legacyOperations: [UpdatePiholeOperation] = []
        var v6Operations: [UpdatePiholeV6Operation] = []
        var adguardOperations: [UpdateAdGuardHomeOperation] = []

        for pihole in piholes.values {
            switch pihole.backendType {
            case .piholeV6:
                Log.debug("Creating operation for \(pihole.identifier)")
                let operation = UpdatePiholeV6Operation(pihole)
                v6Operations.append(operation)
            case .piholeV5:
                Log.debug("Creating operation for \(pihole.identifier)")
                let operation = UpdatePiholeOperation(pihole)
                legacyOperations.append(operation)
            case .adguardHome:
                Log.debug("Creating operation for \(pihole.identifier)")
                let operation = UpdateAdGuardHomeOperation(pihole)
                adguardOperations.append(operation)
            }
        }

        let completionOperation = BlockOperation { [weak self, legacyOperations, v6Operations, adguardOperations] in
            guard let self else { return }

            for operation in legacyOperations {
                self.piholes[operation.pihole.identifier] = operation.pihole
            }
            for operation in v6Operations {
                self.piholes[operation.pihole.identifier] = operation.pihole
            }
            for operation in adguardOperations {
                self.piholes[operation.pihole.identifier] = operation.pihole
            }

            self.updateNetworkOverview()
        }

        for operation in legacyOperations {
            completionOperation.addDependency(operation)
            operationQueue.addOperation(operation)
        }
        for operation in v6Operations {
            completionOperation.addDependency(operation)
            operationQueue.addOperation(operation)
        }
        for operation in adguardOperations {
            completionOperation.addDependency(operation)
            operationQueue.addOperation(operation)
        }

        operationQueue.addOperation(completionOperation)
    }

    private func updateNetworkOverview() {
        Log.debug("Updating Network Overview")

        let newOverview = PiholeNetworkOverview(
            networkStatus: networkStatus(),
            canBeManaged: canManage(),
            totalQueriesToday: networkTotalQueries(),
            adsBlockedToday: networkBlockedQueries(),
            adsPercentageToday: networkPercentageBlocked(),
            averageBlocklist: networkBlocklist(),
            piholes: piholes
        )
        networkOverview = newOverview

        WidgetSnapshotStore.write(WidgetSnapshot(from: newOverview))
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func networkTotalQueries() -> Int {
        var queries: Int = 0
        piholes.values.forEach {
            queries += $0.summary?.dnsQueriesToday ?? 0
        }
        return queries
    }

    private func networkBlockedQueries() -> Int {
        var queries: Int = 0
        piholes.values.forEach {
            queries += $0.summary?.adsBlockedToday ?? 0
        }
        return queries
    }

    private func networkPercentageBlocked() -> Double {
        let totalQueries = networkTotalQueries()
        let blockedQueries = networkBlockedQueries()
        if totalQueries == 0 || blockedQueries == 0 {
            return 0.0
        }
        return Double(blockedQueries) / Double(totalQueries) * 100.0
    }

    private func networkBlocklist() -> Int {
        var blocklistCounts: [Int] = []
        piholes.values.forEach {
            blocklistCounts.append($0.summary?.domainsBeingBlocked ?? 0)
        }
        return blocklistCounts.average()
    }

    private func networkStatus() -> PiholeNetworkStatus {
        var summaries: [PiholeAPISummary] = []
        piholes.values.forEach {
            if let summary = $0.summary { summaries.append(summary) }
        }

        if piholes.isEmpty {
            return .noneSet
        } else if summaries.isEmpty {
            return .offline
        } else if summaries.count < piholes.count {
            return .partiallyOffline
        }

        var status = Set<String>()
        summaries.forEach {
            status.insert($0.status)
        }
        if status.count == 1 {
            guard let statusString = status.first else { return .offline }
            if statusString == "enabled" {
                return .enabled
            } else {
                return .disabled
            }
        } else {
            return .partiallyEnabled
        }
    }

    private func canManage() -> Bool {
        for pihole in piholes.values where pihole.canBeManaged ?? false {
            return true
        }

        return false
    }
}
