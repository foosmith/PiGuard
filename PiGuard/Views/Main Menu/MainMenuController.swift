//
//  MainMenuController.swift
//  PiGuard
//
//  Created by Brad Root on 5/17/20.
//  Copyright © 2020 Brad Root. All rights reserved.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Cocoa
import HotKey

class MainMenuController: NSObject, NSMenuDelegate, PreferencesDelegate, PiGuardManagerDelegate {
    private let toggleHotKey = HotKey(key: .p, modifiers: [.command, .option, .shift])
    private let activitySymbolNames = [
        "arrow.triangle.2.circlepath",
        "arrow.clockwise",
        "arrow.triangle.2.circlepath.circle.fill",
        "arrow.counterclockwise",
    ]

    private let manager: PiGuardManager = PiGuardManager()

    private var networkOverview: PiholeNetworkOverview?
    private var isSyncInProgress = false
    private var isGravityUpdateInProgress = false
    private var menuBarActivityTimer: Timer?
    private var menuBarActivityFrame = 0

    // MARK: - Internal Views

    private let statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private lazy var preferencesWindowController = NSStoryboard(
        name: "Main",
        bundle: nil
    ).instantiateController(
        withIdentifier: "PreferencesWindowContoller"
    ) as? PreferencesWindowController

    private lazy var aboutWindowController = NSStoryboard(
        name: "Main",
        bundle: nil
    ).instantiateController(
        withIdentifier: "AboutWindowController"
    ) as? NSWindowController

    private lazy var syncSettingsWindow: NSWindow = {
        let vc = SyncSettingsViewController()
        vc.delegate = self
        let window = NSWindow(contentViewController: vc)
        window.title = "Sync Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 940, height: 680))
        window.minSize = NSSize(width: 940, height: 680)
        window.center()
        return window
    }()

    // MARK: - Outlets

    @IBOutlet var mainMenu: NSMenu!
    @IBOutlet var mainNetworkStatusMenuItem: NSMenuItem!
    @IBOutlet var mainTotalQueriesMenuItem: NSMenuItem!
    @IBOutlet var mainTotalBlockedMenuItem: NSMenuItem!
    @IBOutlet var mainBlocklistMenuItem: NSMenuItem!
    @IBOutlet var disableNetworkMenuItem: NSMenuItem!
    @IBOutlet var enableNetworkMenuItem: NSMenuItem!
    @IBOutlet var webAdminMenuItem: NSMenuItem!
    @IBOutlet var syncSettingsMenuItem: NSMenuItem!
    @IBOutlet var syncNowMenuItem: NSMenuItem!
    @IBOutlet var updateGravityMenuItem: NSMenuItem!


    // MARK: - Sub-menus for Multi-hole Setups

    private var networkStatusMenu = NSMenu()
    private var networkStatusMenuItems: [String: NSMenuItem] = [:]

    private var totalQueriesMenu = NSMenu()
    private var totalQueriesMenuItems: [String: NSMenuItem] = [:]

    private var totalBlockedMenu = NSMenu()
    private var totalBlockedMenuItems: [String: NSMenuItem] = [:]

    private var blocklistMenu = NSMenu()
    private var blocklistMenuItems: [String: NSMenuItem] = [:]

    private var webAdminMenu = NSMenu()
    private var webAdminMenuItems: [String: NSMenuItem] = [:]

    // MARK: - Actions

    @IBAction func configureMenuBarAction(_: NSMenuItem) {
        preferencesWindowController?.showWindow(self)
    }

    @IBAction func quitMenuBarAction(_: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }

    @IBAction func disableMenuBarAction(_ sender: NSMenuItem) {
        let seconds = sender.tag > 0 ? sender.tag : nil
        Log.info("Disabling via Menu for \(String(describing: seconds)) seconds")
        manager.disableNetwork(seconds: seconds)
    }

    @IBAction func enableMenuBarAction(_: NSMenuItem) {
        manager.enableNetwork()
    }

    @IBAction func aboutAction(_: NSMenuItem) {
        aboutWindowController?.showWindow(self)
    }

    @IBAction func syncSettingsAction(_: NSMenuItem) {
        syncSettingsWindow.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    @IBAction func syncNowAction(_: NSMenuItem) {
        manager.syncNow()
    }

    @IBAction func updateGravityAction(_: NSMenuItem) {
        manager.updateGravityOnNetwork()
    }

    // MARK: - View Lifecycle

    override init() {
        super.init()
        manager.delegate = self
    }

    override func awakeFromNib() {
        if let statusBarButton = statusBarItem.button {
            statusBarButton.image = menuBarImage()
            statusBarButton.imagePosition = .imageLeading
            statusBarButton.title = "Initializing"
        }
        statusBarItem.menu = mainMenu
        mainMenu.delegate = self

        enableKeyboardShortcut()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncBegan), name: .piGuardSyncBegan, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncEnded), name: .piGuardSyncEnded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleGravityBegan), name: .piGuardGravityBegan, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleGravityEnded), name: .piGuardGravityEnded, object: nil)

        if let viewController = preferencesWindowController?.contentViewController as? PreferencesViewController {
            viewController.delegate = self
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        menuBarActivityTimer?.invalidate()
    }

    // MARK: - Keyboard Shortcut

    fileprivate func enableKeyboardShortcut() {
        if Preferences.standard.shortcutEnabled {
            toggleHotKey.isPaused = false
            toggleHotKey.keyDownHandler = {
                Log.debug("Toggling Network from Keyboard Shortcut")
                self.manager.toggleNetwork()
            }
        }
    }

    fileprivate func disableKeyboardShortcut() {
        if !Preferences.standard.shortcutEnabled {
            toggleHotKey.isPaused = true
        }
    }

    // MARK: - Delegate Methods

    internal func updatedConnections() {
        Log.debug("Connections Updated")
        clearSubmenus()
        manager.loadConnections()
        DispatchQueue.main.async {
            self.setupWebAdminMenus()
        }
    }

    internal func updateNetwork(_ network: PiholeNetworkOverview) {
        networkOverview = network
        updateInterface()
        DispatchQueue.main.async {
            self.setupWebAdminMenus()
        }
    }

    // MARK: - Functions

    @objc func launchWebAdmin(sender: NSMenuItem) {
        if sender.title == "Admin Console" {
            guard let piholeIdentifier = networkOverview?.piholes.keys.first else {
                Log.debug("No servers found.")
                return
            }
            launchWebAdmin(for: piholeIdentifier)
        } else {
            let identifier = sender.representedObject as? String ?? sender.title
            launchWebAdmin(for: identifier)
        }
    }

    private func launchWebAdmin(for identifier: String) {
        guard let pihole = networkOverview?.piholes[identifier] else {
            Log.debug("Could not find server with identifier \(identifier)")
            return
        }
        if let legacyAPI = pihole.api, let adminURL = URL(string: legacyAPI.connection.adminPanelURL) {
            NSWorkspace.shared.open(adminURL)
        } else if let newAPI = pihole.api6, let adminURL = URL(string: newAPI.connection.adminPanelURL) {
            NSWorkspace.shared.open(adminURL)
        } else if let adguardAPI = pihole.apiAdguard, let adminURL = URL(string: adguardAPI.connection.adminPanelURL) {
            NSWorkspace.shared.open(adminURL)
        }
    }

    // MARK: - UI Updates

    internal func applyLoggingPreference() {
        manager.applyLoggingPreference()
    }

    internal func updatedPreferences() {
        Log.debug("Preferences Updated")

        updateInterface()

        if Preferences.standard.shortcutEnabled {
            enableKeyboardShortcut()
        } else if !Preferences.standard.shortcutEnabled {
            disableKeyboardShortcut()
        }

        manager.setPollingRate(to: Preferences.standard.pollingRate)
        manager.restartSyncTimer()
    }

    private func updateInterface() {
        Log.debug("Updating Interface")

        DispatchQueue.main.async {
            self.refreshMenuBarDisplay()
            self.updateStatusButtons()
            self.updateMenuButtons()
            self.updateStatusSubmenus()
        }
    }

    private func setMenuBarTitle(_ title: String) {
        Log.debug("Set Button Title: \(title)")

        if let statusBarButton = statusBarItem.button {
            DispatchQueue.main.async {
                statusBarButton.image = self.menuBarImage()
                if title.isEmpty {
                    statusBarButton.imagePosition = .imageOnly
                } else {
                    statusBarButton.imagePosition = .imageLeading
                    statusBarButton.title = title
                }
            }
        }
    }

    private func updateMenuBarTitle() {
        guard let networkOverview = networkOverview else { return }
        let currentStatus = networkOverview.networkStatus

        var titleElements: [String] = []

        if currentStatus == .enabled || currentStatus == .partiallyEnabled {
            let showLabels = Preferences.standard.showLabels
            let verboseLabels = Preferences.standard.verboseLabels
            if Preferences.standard.showQueries {
                if showLabels {
                    let label = verboseLabels ? "Queries:" : "Q:"
                    titleElements.append(label)
                }
                titleElements.append(networkOverview.totalQueriesToday.string)
                if Preferences.standard.showBlocked || Preferences.standard.showPercentage, showLabels {
                    titleElements.append("•")
                }
            }
            if Preferences.standard.showBlocked {
                if showLabels {
                    let label = verboseLabels ? "Blocked:" : "B:"
                    titleElements.append(label)
                }
                if Preferences.standard.showQueries, !showLabels {
                    titleElements.append("/")
                }
                titleElements.append(networkOverview.adsBlockedToday.string)
            }

            if Preferences.standard.showPercentage {
                if Preferences.standard.showBlocked || (Preferences.standard.showQueries && !showLabels) {
                    titleElements.append("(\(networkOverview.adsPercentageToday.string))")
                } else {
                    if showLabels {
                        let label = verboseLabels ? "Blocked:" : "B:"
                        titleElements.append(label)
                    }
                    titleElements.append("\(networkOverview.adsPercentageToday.string)")
                }
            }
        } else {
            titleElements = [currentStatus.rawValue]
        }

        // Set title
        let titleString = titleElements.joined(separator: " ")
        setMenuBarTitle(titleString)
    }

    private func menuBarImage() -> NSImage? {
        if isSyncInProgress || isGravityUpdateInProgress {
            let index = menuBarActivityFrame % activitySymbolNames.count
            let image = NSImage(
                systemSymbolName: activitySymbolNames[index],
                accessibilityDescription: "Activity in progress"
            )
            image?.isTemplate = true
            return image
        }

        let image = NSImage(named: "icon")
        image?.isTemplate = true
        return image
    }

    private func refreshMenuBarDisplay() {
        if let title = menuBarActivityTitle() {
            setMenuBarTitle(title)
        } else {
            menuBarActivityTimer?.invalidate()
            menuBarActivityTimer = nil
            updateMenuBarTitle()
        }
    }

    private func updateMenuBarActivityState() {
        menuBarActivityFrame = 0

        guard menuBarActivityTitle() != nil else {
            menuBarActivityTimer?.invalidate()
            menuBarActivityTimer = nil
            refreshMenuBarDisplay()
            return
        }

        if menuBarActivityTimer == nil {
            let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(advanceMenuBarActivityFrame), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            menuBarActivityTimer = timer
        }

        refreshMenuBarDisplay()
    }

    @objc private func advanceMenuBarActivityFrame() {
        guard menuBarActivityTitle() != nil else { return }
        menuBarActivityFrame = (menuBarActivityFrame + 1) % 4
        refreshMenuBarDisplay()
    }

    private func menuBarActivityTitle() -> String? {
        guard isSyncInProgress || isGravityUpdateInProgress else { return nil }
        let base = menuBarBaseTitle()
        let status: String

        if isSyncInProgress && isGravityUpdateInProgress {
            status = "Syncing + refreshing"
        } else if isSyncInProgress {
            status = "Syncing"
        } else {
            status = refreshActivityTitle()
        }

        return base.isEmpty ? status : "\(base)  \(status)"
    }

    private func refreshActivityTitle() -> String {
        guard let networkOverview = networkOverview else { return "Refreshing" }
        let backends = networkOverview.piholes.values.map(\.backendType)
        let hasAdGuard = backends.contains(.adguardHome)
        let hasV6 = backends.contains(.piholeV6)

        if hasAdGuard && hasV6 {
            return "Refreshing filters + gravity"
        } else if hasAdGuard {
            return "Refreshing filters"
        } else {
            return "Updating gravity"
        }
    }

    private func menuBarBaseTitle() -> String {
        guard let networkOverview = networkOverview else { return "" }
        let currentStatus = networkOverview.networkStatus
        var titleElements: [String] = []

        if currentStatus == .enabled || currentStatus == .partiallyEnabled {
            let showLabels = Preferences.standard.showLabels
            let verboseLabels = Preferences.standard.verboseLabels
            if Preferences.standard.showQueries {
                if showLabels {
                    let label = verboseLabels ? "Queries:" : "Q:"
                    titleElements.append(label)
                }
                titleElements.append(networkOverview.totalQueriesToday.string)
                if Preferences.standard.showBlocked || Preferences.standard.showPercentage, showLabels {
                    titleElements.append("•")
                }
            }
            if Preferences.standard.showBlocked {
                if showLabels {
                    let label = verboseLabels ? "Blocked:" : "B:"
                    titleElements.append(label)
                }
                if Preferences.standard.showQueries, !showLabels {
                    titleElements.append("/")
                }
                titleElements.append(networkOverview.adsBlockedToday.string)
            }

            if Preferences.standard.showPercentage {
                if Preferences.standard.showBlocked || (Preferences.standard.showQueries && !showLabels) {
                    titleElements.append("(\(networkOverview.adsPercentageToday.string))")
                } else {
                    if showLabels {
                        let label = verboseLabels ? "Blocked:" : "B:"
                        titleElements.append(label)
                    }
                    titleElements.append("\(networkOverview.adsPercentageToday.string)")
                }
            }
        } else {
            titleElements = [currentStatus.rawValue]
        }

        return titleElements.joined(separator: " ")
    }

    @objc private func handleSyncBegan() {
        isSyncInProgress = true
        updateMenuBarActivityState()
        updateMenuButtons()
    }

    @objc private func handleSyncEnded() {
        isSyncInProgress = false
        updateMenuBarActivityState()
        updateMenuButtons()
    }

    @objc private func handleGravityBegan() {
        isGravityUpdateInProgress = true
        updateMenuBarActivityState()
        updateMenuButtons()
    }

    @objc private func handleGravityEnded() {
        isGravityUpdateInProgress = false
        updateMenuBarActivityState()
        updateMenuButtons()
    }

    private func updateStatusButtons() {
        guard let networkOverview = networkOverview else { return }
        mainNetworkStatusMenuItem.title = "Status: \(networkOverview.networkStatus.rawValue)"
        mainTotalQueriesMenuItem.title = "Queries: \(networkOverview.totalQueriesToday.string)"
        mainTotalBlockedMenuItem.title = "Blocked: " +
            "\(networkOverview.adsBlockedToday.string) " +
            "(\(networkOverview.adsPercentageToday.string))"
        mainBlocklistMenuItem.title = "Blocklist: \(networkOverview.averageBlocklist.string)"

        updateStatusSubmenus()
    }

    private func updateStatusSubmenus() {
        guard let networkOverview = networkOverview else { return }
        guard let mainMenu = mainNetworkStatusMenuItem.menu else { return }

        let piholes = networkOverview.piholes
        if piholes.count > 1 {
            let sortedPiholes = piholes.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            for pihole in sortedPiholes {
                let identifier = pihole.identifier
                let displayName = pihole.displayName

                // Status Submenu
                if networkStatusMenuItems[identifier] == nil {
                    let menuItem = NSMenuItem(
                        title: "\(displayName): Initializing",
                        action: nil,
                        keyEquivalent: ""
                    )
                    networkStatusMenuItems[identifier] = menuItem
                    networkStatusMenu.addItem(menuItem)
                }

                if !mainNetworkStatusMenuItem.hasSubmenu {
                    mainMenu.setSubmenu(networkStatusMenu, for: mainNetworkStatusMenuItem)
                    mainNetworkStatusMenuItem.isEnabled = true
                }

                if let menuItem = networkStatusMenuItems[identifier] {
                    menuItem.title = "\(displayName): \(pihole.status.rawValue)"
                }

                // Total Queries Submenu
                if totalQueriesMenuItems[identifier] == nil {
                    let menuItem = NSMenuItem(
                        title: "\(displayName): 0",
                        action: nil,
                        keyEquivalent: ""
                    )
                    totalQueriesMenuItems[identifier] = menuItem
                    totalQueriesMenu.addItem(menuItem)
                }

                if !mainTotalQueriesMenuItem.hasSubmenu {
                    mainMenu.setSubmenu(totalQueriesMenu, for: mainTotalQueriesMenuItem)
                    mainTotalQueriesMenuItem.isEnabled = true
                }

                if let menuItem = totalQueriesMenuItems[identifier] {
                    menuItem.title = "\(displayName): \((pihole.summary?.dnsQueriesToday ?? 0).string)"
                }

                // Total Blocked Submenu
                if totalBlockedMenuItems[identifier] == nil {
                    let menuItem = NSMenuItem(
                        title: "\(displayName): 0 (100%)",
                        action: nil,
                        keyEquivalent: ""
                    )
                    totalBlockedMenuItems[identifier] = menuItem
                    totalBlockedMenu.addItem(menuItem)
                }

                if !mainTotalBlockedMenuItem.hasSubmenu {
                    mainMenu.setSubmenu(totalBlockedMenu, for: mainTotalBlockedMenuItem)
                    mainTotalBlockedMenuItem.isEnabled = true
                }

                if let menuItem = totalBlockedMenuItems[identifier] {
                    menuItem.title = "\(displayName): " +
                        "\((pihole.summary?.adsBlockedToday ?? 0).string) " +
                        "(\((pihole.summary?.adsPercentageToday ?? 100.0).string))"
                }

                // Blocklist Submenu
                if blocklistMenuItems[identifier] == nil {
                    let menuItem = NSMenuItem(
                        title: "\(displayName): 0",
                        action: nil,
                        keyEquivalent: ""
                    )
                    blocklistMenuItems[identifier] = menuItem
                    blocklistMenu.addItem(menuItem)
                }

                if !mainBlocklistMenuItem.hasSubmenu {
                    mainMenu.setSubmenu(blocklistMenu, for: mainBlocklistMenuItem)
                    mainBlocklistMenuItem.isEnabled = true
                }

                if let menuItem = blocklistMenuItems[identifier] {
                    menuItem.title = "\(displayName): \((pihole.summary?.domainsBeingBlocked ?? 0).string)"
                }
            }
        }
    }

    private func setupWebAdminMenus() {
        guard let networkOverview = networkOverview else { return }
        guard let mainMenu = mainNetworkStatusMenuItem.menu else { return }
        let piholes = networkOverview.piholes

        if piholes.count > 1 {
            let sortedPiholes = piholes.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            for pihole in sortedPiholes {
                let identifier = pihole.identifier
                // Web Admin Submenu
                if webAdminMenuItems[identifier] == nil {
                    let menuItem = NSMenuItem(
                        title: pihole.displayName,
                        action: #selector(launchWebAdmin(sender:)),
                        keyEquivalent: ""
                    )
                    menuItem.isEnabled = true
                    menuItem.target = self
                    menuItem.representedObject = identifier
                    webAdminMenuItems[identifier] = menuItem
                    webAdminMenu.addItem(menuItem)
                } else {
                    webAdminMenuItems[identifier]?.title = pihole.displayName
                    webAdminMenuItems[identifier]?.representedObject = identifier
                }

                if !webAdminMenuItem.hasSubmenu {
                    mainMenu.setSubmenu(webAdminMenu, for: webAdminMenuItem)
                    webAdminMenuItem.isEnabled = true
                }
            }
        } else if piholes.count == 1 {
            webAdminMenuItem.target = self
            webAdminMenuItem.action = #selector(launchWebAdmin(sender:))
            webAdminMenuItem.isEnabled = true
        }
    }

    // MARK: - Sync Settings Delegate

    private func clearSubmenus() {
        guard let mainMenu = mainNetworkStatusMenuItem.menu else { return }
        if mainNetworkStatusMenuItem.hasSubmenu {
            mainMenu.setSubmenu(nil, for: mainNetworkStatusMenuItem)
            networkStatusMenu.removeAllItems()
            networkStatusMenuItems.removeAll()
        }

        if mainTotalQueriesMenuItem.hasSubmenu {
            mainMenu.setSubmenu(nil, for: mainTotalQueriesMenuItem)
            totalQueriesMenu.removeAllItems()
            totalQueriesMenuItems.removeAll()
        }

        if mainTotalBlockedMenuItem.hasSubmenu {
            mainMenu.setSubmenu(nil, for: mainTotalBlockedMenuItem)
            totalBlockedMenu.removeAllItems()
            totalBlockedMenuItems.removeAll()
        }

        if mainBlocklistMenuItem.hasSubmenu {
            mainMenu.setSubmenu(nil, for: mainBlocklistMenuItem)
            blocklistMenu.removeAllItems()
            blocklistMenuItems.removeAll()
        }

        if webAdminMenuItem.hasSubmenu {
            mainMenu.setSubmenu(nil, for: webAdminMenuItem)
            webAdminMenu.removeAllItems()
            webAdminMenuItems.removeAll()
        }
        webAdminMenuItem.action = nil
        webAdminMenuItem.isEnabled = false
    }

    private func updateMenuButtons() {

        guard let networkOverview = networkOverview else { return }
        let currentStatus = networkOverview.networkStatus
        let backends = networkOverview.piholes.values.map(\.backendType)
        let hasAdGuard = backends.contains(.adguardHome)
        let v6Count = backends.filter { $0 == .piholeV6 }.count
        let hasV6 = v6Count > 0
        let isBusy = isSyncInProgress || isGravityUpdateInProgress

        if !networkOverview.canBeManaged {
            disableNetworkMenuItem.isEnabled = false
            enableNetworkMenuItem.isEnabled = false
        } else if currentStatus == .enabled || currentStatus == .partiallyEnabled {
            enableNetworkMenuItem.isEnabled = false
            enableNetworkMenuItem.isHidden = true
            disableNetworkMenuItem.isEnabled = true
            disableNetworkMenuItem.isHidden = false
        } else if currentStatus == .disabled {
            enableNetworkMenuItem.isEnabled = true
            enableNetworkMenuItem.isHidden = false
            disableNetworkMenuItem.isEnabled = false
            disableNetworkMenuItem.isHidden = true
        } else {
            disableNetworkMenuItem.isEnabled = false
            enableNetworkMenuItem.isEnabled = false
        }

        if hasAdGuard {
            disableNetworkMenuItem.title = "Disable Blocking"
            enableNetworkMenuItem.title = "Enable Blocking"
        } else if networkOverview.piholes.count > 1 {
            disableNetworkMenuItem.title = "Disable Pi-holes"
            enableNetworkMenuItem.title = "Enable Pi-holes"
        } else {
            disableNetworkMenuItem.title = "Disable Pi-hole"
            enableNetworkMenuItem.title = "Enable Pi-hole"
        }

        if hasAdGuard && hasV6 {
            updateGravityMenuItem.title = "Refresh Filters / Update Gravity"
        } else if hasAdGuard {
            updateGravityMenuItem.title = "Refresh Filters"
        } else {
            updateGravityMenuItem.title = "Update Gravity"
        }

        let hasRefreshableBackend = hasV6 || hasAdGuard
        let canSync = v6Count >= 2
        updateGravityMenuItem.isHidden = !hasRefreshableBackend
        updateGravityMenuItem.isEnabled = hasRefreshableBackend && networkOverview.canBeManaged && !isBusy

        syncSettingsMenuItem.isHidden = !canSync
        syncNowMenuItem.isHidden = !canSync
        syncNowMenuItem.isEnabled = canSync && Preferences.standard.syncEnabled && !isBusy
    }
}

extension MainMenuController: SyncSettingsViewControllerDelegate {
    func syncSettingsUpdated() {
        manager.restartSyncTimer()
    }

    func syncNowRequestedFromSettings() {
        manager.syncNow()
    }
}
