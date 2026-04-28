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
    private var isFetchingTopItems = false
    private var cachedTopBlocked: [String: [TopItem]] = [:]
    private var cachedTopClients: [String: [TopItem]] = [:]
    private var queryLogWindowController: QueryLogWindowController?
    private var pendingOpenQueryLog = false
    private var flagWatchSource: DispatchSourceFileSystemObject?

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
        window.setContentSize(NSSize(width: 760, height: 620))
        window.minSize = NSSize(width: 760, height: 620)
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
    @IBOutlet var topBlockedMenuItem: NSMenuItem!
    @IBOutlet var topClientsMenuItem: NSMenuItem!
    @IBOutlet var queryLogMenuItem: NSMenuItem!
    #if !APPSTORE
    private var checkForUpdatesMenuItem: NSMenuItem?
    #endif


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

    #if !APPSTORE
    @objc func checkForUpdatesAction(_ sender: NSMenuItem) {
        UpdateManager.shared.checkForUpdates()
    }
    #endif

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

    @IBAction func queryLogAction(_: NSMenuItem) {
        guard let networkOverview = networkOverview else { return }
        if queryLogWindowController?.window?.isVisible == true {
            queryLogWindowController?.window?.makeKeyAndOrderFront(self)
        } else {
            queryLogWindowController = QueryLogWindowController(piholes: networkOverview.piholes)
            queryLogWindowController?.showWindow(self)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handleOpenQueryLog() {
        Log.debug("Widget tap received — opening Query Log (networkOverview ready: \(networkOverview != nil))")
        if networkOverview != nil {
            queryLogAction(queryLogMenuItem)
        } else {
            pendingOpenQueryLog = true
        }
    }

    // MARK: - View Lifecycle

    override init() {
        super.init()
        _trace("MainMenuController.init()")
        manager.delegate = self
    }

    override func awakeFromNib() {
        _trace("awakeFromNib() — setting up status bar item")
        if let statusBarButton = statusBarItem.button {
            let image = menuBarImage()
            statusBarButton.image = image
            statusBarButton.imagePosition = image == nil ? .noImage : .imageLeading
            statusBarButton.title = "Initializing"
            _trace("awakeFromNib() — statusBarButton configured, image=\(image != nil), hideMenuBarIcon=\(Preferences.standard.hideMenuBarIcon)")
        } else {
            _trace("awakeFromNib() — WARNING: statusBarItem.button is nil (no space in menu bar?)")
        }
        statusBarItem.menu = mainMenu
        mainMenu.delegate = self

        #if !APPSTORE
        // Insert "Check for Updates…" after the "About PiGuard" menu item
        if let aboutIndex = mainMenu.items.firstIndex(where: { $0.title.hasPrefix("About") }) {
            let item = NSMenuItem(
                title: "Check for Updates\u{2026}",
                action: #selector(checkForUpdatesAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            mainMenu.insertItem(item, at: aboutIndex + 1)
            checkForUpdatesMenuItem = item
        }
        #endif

        enableKeyboardShortcut()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncBegan), name: .piGuardSyncBegan, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncEnded), name: .piGuardSyncEnded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleGravityBegan), name: .piGuardGravityBegan, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleGravityEnded), name: .piGuardGravityEnded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenQueryLog), name: .piGuardOpenQueryLog, object: nil)

        // DistributedNotificationCenter: widget tap or second-instance signal → open Query Log.
        startDarwinNotificationListener()

        // File-based fallback: if the flag was written while we were not running
        // (no Darwin listener active), consume it at startup.
        startFlagFileWatcher()

        if let viewController = preferencesWindowController?.contentViewController as? PreferencesViewController {
            viewController.delegate = self
        }

        // Show preferences on first launch so the app presents a window immediately.
        // Without this, LSUIElement apps appear to do nothing when opened.
        if Preferences.standard.piholes.isEmpty {
            DispatchQueue.main.async {
                self.preferencesWindowController?.showWindow(self)
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        _trace("awakeFromNib() — complete")
    }

    private func startDarwinNotificationListener() {
        // Local notification — received when perform() runs in the main app
        // process (openAppWhenRun = true routes the intent here on macOS).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenQueryLog),
            name: Notification.Name("com.foosmith.PiGuard.openQueryLog"),
            object: nil
        )

        // Distributed notification — received when perform() runs in the widget
        // extension process, or when a second app instance signals via main.swift.
        // Goes through distnoted and crosses the sandbox boundary.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleOpenQueryLog),
            name: Notification.Name("com.foosmith.PiGuard.openQueryLog"),
            object: nil
        )
    }

    private func startFlagFileWatcher() {
        // Watch the App Group container — writable by both the widget extension
        // (via AppIntent) and by any second instance of the main app.
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.foosmith.PiGuard")
        else {
            Log.debug("Widget watcher: App Group container unavailable")
            return
        }
        let flagURL = groupURL.appendingPathComponent("open_query_log.flag")

        // Consume any flag that was written while we were not running.
        if FileManager.default.fileExists(atPath: flagURL.path) {
            try? FileManager.default.removeItem(at: flagURL)
            Log.debug("Widget tap flag found at startup — will open Query Log when ready")
            pendingOpenQueryLog = true
        }

        // Open the directory for vnode watching (O_EVTONLY = watch only, no I/O).
        let fd = Darwin.open(groupURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            guard FileManager.default.fileExists(atPath: flagURL.path) else { return }
            try? FileManager.default.removeItem(at: flagURL)
            Log.debug("Widget tap flag detected — opening Query Log")
            self.handleOpenQueryLog()
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        flagWatchSource = source
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: Notification.Name("com.foosmith.PiGuard.openQueryLog"),
            object: nil
        )
        flagWatchSource?.cancel()
        flagWatchSource = nil
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

    internal func updatedConnections(_ connections: [PiholeConnectionV4]) {
        Log.debug("Connections Updated")
        clearSubmenus()
        manager.loadConnections(connections)
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
        if pendingOpenQueryLog {
            pendingOpenQueryLog = false
            DispatchQueue.main.async { self.queryLogAction(self.queryLogMenuItem) }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu == mainMenu, !isFetchingTopItems else { return }
        isFetchingTopItems = true

        guard let networkOverview = networkOverview else {
            isFetchingTopItems = false
            return
        }

        Task {
            var allTopBlocked: [String: [TopItem]] = [:]
            var allTopClients: [String: [TopItem]] = [:]

            for pihole in networkOverview.piholes.values {
                if let api = pihole.api {
                    allTopBlocked[pihole.identifier] = await api.fetchTopBlocked()
                    allTopClients[pihole.identifier] = await api.fetchTopClients()
                } else if let api6 = pihole.api6 {
                    allTopBlocked[pihole.identifier] = await api6.fetchTopBlocked()
                    allTopClients[pihole.identifier] = await api6.fetchTopClients()
                } else if let apiAdguard = pihole.apiAdguard {
                    if let stats = await apiAdguard.fetchFullStats() {
                        allTopBlocked[pihole.identifier] = stats.topBlockedDomains
                        allTopClients[pihole.identifier] = stats.topClients
                    }
                }
            }

            await MainActor.run {
                self.cachedTopBlocked = allTopBlocked
                self.cachedTopClients = allTopClients
                self.rebuildTopBlockedSubmenu()
                self.rebuildTopClientsSubmenu()
                self.isFetchingTopItems = false
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu == mainMenu else { return }
        isFetchingTopItems = false
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
                let image = self.menuBarImage()
                statusBarButton.image = image
                if image == nil {
                    statusBarButton.imagePosition = .noImage
                    statusBarButton.title = title
                } else if title.isEmpty {
                    statusBarButton.imagePosition = .imageOnly
                } else {
                    statusBarButton.imagePosition = .imageLeading
                    statusBarButton.title = title
                }
            }
        }
    }

    private func updateMenuBarTitle() {
        setMenuBarTitle(menuBarBaseTitle())
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

        if Preferences.standard.hideMenuBarIcon {
            return nil
        }

        let image = NSImage(named: "icon")
        image?.isTemplate = false
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

    private func rebuildTopBlockedSubmenu() {
        guard let submenu = topBlockedMenuItem.submenu else { return }
        submenu.removeAllItems()

        guard let networkOverview = networkOverview else {
            submenu.addItem(NSMenuItem(title: "Unavailable", action: nil, keyEquivalent: ""))
            return
        }

        let sortedPiholes = networkOverview.piholes.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        let showServerNames = sortedPiholes.count > 1

        for (index, pihole) in sortedPiholes.enumerated() {
            if showServerNames {
                if index > 0 { submenu.addItem(NSMenuItem.separator()) }
                let header = NSMenuItem(title: pihole.displayName, action: nil, keyEquivalent: "")
                header.isEnabled = false
                submenu.addItem(header)
            }

            let items = cachedTopBlocked[pihole.identifier] ?? []
            if items.isEmpty {
                let empty = NSMenuItem(title: "No data", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                submenu.addItem(empty)
            } else {
                for item in items {
                    let menuItem = NSMenuItem(title: "\(item.name)  (\(item.count.string))", action: nil, keyEquivalent: "")
                    menuItem.isEnabled = false
                    submenu.addItem(menuItem)
                }
            }
        }
    }

    private func rebuildTopClientsSubmenu() {
        guard let submenu = topClientsMenuItem.submenu else { return }
        submenu.removeAllItems()

        guard let networkOverview = networkOverview else {
            submenu.addItem(NSMenuItem(title: "Unavailable", action: nil, keyEquivalent: ""))
            return
        }

        let sortedPiholes = networkOverview.piholes.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        let showServerNames = sortedPiholes.count > 1

        for (index, pihole) in sortedPiholes.enumerated() {
            if showServerNames {
                if index > 0 { submenu.addItem(NSMenuItem.separator()) }
                let header = NSMenuItem(title: pihole.displayName, action: nil, keyEquivalent: "")
                header.isEnabled = false
                submenu.addItem(header)
            }

            let items = cachedTopClients[pihole.identifier] ?? []
            if items.isEmpty {
                let empty = NSMenuItem(title: "No data", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                submenu.addItem(empty)
            } else {
                for item in items {
                    let menuItem = NSMenuItem(title: "\(item.name)  (\(item.count.string))", action: nil, keyEquivalent: "")
                    menuItem.isEnabled = false
                    submenu.addItem(menuItem)
                }
            }
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

        cachedTopBlocked.removeAll()
        cachedTopClients.removeAll()
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
