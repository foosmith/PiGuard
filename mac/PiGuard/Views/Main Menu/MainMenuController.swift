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

class MainMenuController: NSObject, NSMenuDelegate, PreferencesDelegate, PiGuardManagerDelegate {
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
    private var isFetchingHistory = false

    // MARK: - Activity Graph & Diagnosis Messages

    private let activityGraphView = ActivityGraphView(frame: NSRect(x: 0, y: 0, width: 280, height: 96))
    private let activityGraphMenuItem = NSMenuItem()
    private let diagnosisMessagesMenuItem = NSMenuItem()
    private let diagnosisMessagesMenu = NSMenu()
    private let serverUpdatesMenuItem = NSMenuItem()
    private let serverUpdatesMenu = NSMenu()

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
    @IBOutlet var disableNetworkMenuItem: NSMenuItem!
    @IBOutlet var enableNetworkMenuItem: NSMenuItem!
    @IBOutlet var webAdminMenuItem: NSMenuItem!
    @IBOutlet var syncParentMenuItem: NSMenuItem!
    @IBOutlet var syncSettingsMenuItem: NSMenuItem!
    @IBOutlet var syncNowMenuItem: NSMenuItem!
    @IBOutlet var updateGravityMenuItem: NSMenuItem!
    @IBOutlet var topBlockedMenuItem: NSMenuItem!
    @IBOutlet var topClientsMenuItem: NSMenuItem!
    @IBOutlet var queryLogMenuItem: NSMenuItem!


    // MARK: - Sub-menus for Multi-hole Setups

    private var networkStatusMenu = NSMenu()
    private var networkStatusMenuItems: [String: NSMenuItem] = [:]

    // MARK: - Timed-disable Countdown

    /// Per-server moments when a timed disable re-enables blocking, derived
    /// from each poll. Drives the "(4:32)" suffix on the status lines.
    private var disabledDeadlines: [String: Date] = [:]
    private var countdownTimer: Timer?

    private var totalQueriesMenu = NSMenu()
    private var totalQueriesMenuItems: [String: NSMenuItem] = [:]

    private var totalBlockedMenu = NSMenu()
    private var totalBlockedMenuItems: [String: NSMenuItem] = [:]

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
        NSApp.setActivationPolicy(.regular)
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
        NSApp.setActivationPolicy(.regular)
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
        manager.delegate = self
    }

    override func awakeFromNib() {
        if let statusBarButton = statusBarItem.button {
            let image = menuBarImage()
            statusBarButton.image = image
            statusBarButton.imagePosition = image == nil ? .noImage : .imageLeading
            statusBarButton.title = "Initializing"
        } else {
            Log.warn("statusBarItem.button is nil (no space in menu bar?)")
        }
        statusBarItem.menu = mainMenu
        mainMenu.delegate = self

        setupActivityGraphMenuItem()
        setupDiagnosisMessagesMenuItem()
        setupServerUpdatesMenuItem()

        NotificationCenter.default.addObserver(self, selector: #selector(handleDiagnosisMessagesUpdated), name: .piGuardDiagnosisMessagesUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleServerUpdatesUpdated), name: .piGuardServerUpdatesUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncBegan), name: .piGuardSyncBegan, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncEnded), name: .piGuardSyncEnded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleGravityBegan), name: .piGuardGravityBegan, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleGravityEnded), name: .piGuardGravityEnded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenQueryLog), name: .piGuardOpenQueryLog, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWindowClosed(_:)), name: NSWindow.willCloseNotification, object: nil)

        // DistributedNotificationCenter: widget tap or second-instance signal → open Query Log.
        startDarwinNotificationListener()

        // File-based fallback: if the flag was written while we were not running
        // (no Darwin listener active), consume it at startup.
        startFlagFileWatcher()

        if let viewController = preferencesWindowController?.contentViewController as? PreferencesViewController {
            viewController.delegate = self
        }

        // Show preferences on first launch so the app presents a window immediately.
        // Without this, LSUIElement apps appear to do nothing when opened from Finder.
        // "hasShownWelcomeWindow" is new in 3.6.5 — unset for all installs (fresh or update),
        // so reviewers and new users both see a window on first launch of this build.
        let hasShownWelcome = Preferences.standard.bool(forKey: "hasShownWelcomeWindow")
        if !hasShownWelcome || Preferences.standard.piholes.isEmpty {
            Preferences.standard.set(true, forKey: "hasShownWelcomeWindow")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard let pwc = self.preferencesWindowController else {
                    Log.warn("preferencesWindowController is nil on first launch")
                    return
                }
                NSApp.setActivationPolicy(.regular)
                pwc.showWindow(self)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
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
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupID)
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
        updateDisabledDeadlines(from: network)
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
        guard menu == mainMenu else { return }
        refreshActivityGraph()

        guard !isFetchingTopItems else { return }
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

    @objc private func handleWindowClosed(_ notification: Notification) {
        DispatchQueue.main.async {
            AppDelegate.revertToAccessoryPolicyIfNeeded()
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
                    // Without an icon, an empty title would leave the status
                    // item invisible and unclickable.
                    statusBarButton.title = title.isEmpty ? "PiGuard" : title
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

        return nil
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
            var title = currentStatus.rawValue
            if currentStatus == .disabled {
                title += countdownSuffix(deadline: disabledDeadlines.values.max())
            }
            titleElements = [title]
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

    private func updateDisabledDeadlines(from network: PiholeNetworkOverview) {
        let now = Date()
        disabledDeadlines = network.piholes.values.reduce(into: [:]) { deadlines, pihole in
            if let remaining = pihole.disabledSecondsRemaining, remaining > 0 {
                deadlines[pihole.identifier] = now.addingTimeInterval(remaining)
            }
        }

        DispatchQueue.main.async {
            if self.disabledDeadlines.isEmpty {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
            } else if self.countdownTimer == nil {
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    self?.updateStatusButtons()
                    self?.updateMenuBarTitle()
                }
                // .common keeps the timer firing while the menu is open
                // (menu tracking runs the run loop in event-tracking mode).
                RunLoop.main.add(timer, forMode: .common)
                self.countdownTimer = timer
            }
        }
    }

    /// " (4:32)" while a timed disable is counting down, otherwise "".
    private func countdownSuffix(deadline: Date?) -> String {
        guard let deadline else { return "" }
        let remaining = Int(deadline.timeIntervalSinceNow.rounded(.up))
        guard remaining > 0 else { return "" }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        let clock = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
        return " (\(clock))"
    }

    private func updateStatusButtons() {
        guard let networkOverview = networkOverview else { return }
        // The network line counts down to the last server coming back.
        let networkDeadline = disabledDeadlines.values.max()
        let networkSuffix = networkOverview.networkStatus == .disabled
            ? countdownSuffix(deadline: networkDeadline)
            : ""
        mainNetworkStatusMenuItem.title = "Status: \(networkOverview.networkStatus.rawValue)\(networkSuffix)"
        mainTotalQueriesMenuItem.title = "Queries: \(networkOverview.totalQueriesToday.string)"
        mainTotalBlockedMenuItem.title = "Blocked: " +
            "\(networkOverview.adsBlockedToday.string) " +
            "(\(networkOverview.adsPercentageToday.string))"

        updateStatusSubmenus()
    }

    private func updateStatusSubmenus() {
        guard let networkOverview = networkOverview else { return }
        guard let mainMenu = mainNetworkStatusMenuItem.menu else { return }

        let piholes = networkOverview.piholes
        let sortedPiholes = piholes.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        for pihole in sortedPiholes {
            let identifier = pihole.identifier
            let displayName = pihole.displayName

            // Status Submenu (only useful with more than one server)
            if piholes.count > 1 {
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
                    let suffix = countdownSuffix(deadline: disabledDeadlines[identifier])
                    menuItem.title = "\(displayName): \(pihole.status.rawValue)\(suffix)"
                }
            }

            // Queries submenu: per-server count plus the blocklist size,
            // which no longer has its own top-level row. Shown for
            // single-server setups too, for the blocklist detail.
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
                menuItem.title = "\(displayName): " +
                    "\((pihole.summary?.dnsQueriesToday ?? 0).string) queries · " +
                    "\((pihole.summary?.domainsBeingBlocked ?? 0).string) blocklist"
            }

            // Blocked submenu, per server.
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
                    "(\((pihole.summary?.adsPercentageToday ?? 0.0).string))"
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

    // MARK: - Activity Graph

    private func setupActivityGraphMenuItem() {
        // Track the menu's width, which longer sibling items may stretch.
        activityGraphView.autoresizingMask = [.width]
        activityGraphMenuItem.view = activityGraphView
        activityGraphMenuItem.isHidden = true
        let insertIndex = mainMenu.index(of: mainTotalBlockedMenuItem) + 1
        mainMenu.insertItem(activityGraphMenuItem, at: insertIndex)
    }

    private func refreshActivityGraph() {
        guard let networkOverview = networkOverview else { return }
        let v6Apis = networkOverview.piholes.values.compactMap(\.api6)
        let adguardApis = networkOverview.piholes.values.compactMap(\.apiAdguard)

        activityGraphMenuItem.isHidden = v6Apis.isEmpty && adguardApis.isEmpty
        guard !activityGraphMenuItem.isHidden, !isFetchingHistory else { return }
        isFetchingHistory = true

        Task {
            // Buckets are aligned to the same 10-minute boundaries on every
            // server, so summing by timestamp merges multi-server setups.
            var piholeBuckets: [Date: (total: Int, blocked: Int)] = [:]
            for api in v6Apis {
                for bucket in await api.fetchHistory() {
                    piholeBuckets[bucket.timestamp, default: (0, 0)].total += bucket.total
                    piholeBuckets[bucket.timestamp, default: (0, 0)].blocked += bucket.blocked
                }
            }

            // AdGuard Home buckets are hourly, aligned to the top of the hour.
            var adguardBuckets: [Date: (total: Int, blocked: Int)] = [:]
            for api in adguardApis {
                for bucket in await api.fetchHistory() {
                    adguardBuckets[bucket.timestamp, default: (0, 0)].total += bucket.total
                    adguardBuckets[bucket.timestamp, default: (0, 0)].blocked += bucket.blocked
                }
            }

            var combined: [Date: (total: Int, blocked: Int)]
            if adguardBuckets.isEmpty {
                combined = piholeBuckets
            } else {
                // Mixed backends: collapse Pi-hole's 10-minute buckets to the
                // same hourly boundaries so both merge at equal granularity.
                combined = adguardBuckets
                for (timestamp, counts) in piholeBuckets {
                    let hourStart = floor(timestamp.timeIntervalSince1970 / 3600) * 3600
                    let hour = Date(timeIntervalSince1970: hourStart)
                    combined[hour, default: (0, 0)].total += counts.total
                    combined[hour, default: (0, 0)].blocked += counts.blocked
                }
                // Pi-hole history spans slightly more than 24 hours, which
                // leaves a partial oldest hour; keep the 24 most recent.
                let kept = Set(combined.keys.sorted().suffix(24))
                combined = combined.filter { kept.contains($0.key) }
            }

            let buckets = combined
                .map { ActivityGraphView.Bucket(timestamp: $0.key, total: $0.value.total, blocked: $0.value.blocked) }

            await MainActor.run {
                self.activityGraphView.update(buckets: buckets)
                self.isFetchingHistory = false
            }
        }
    }

    // MARK: - Diagnosis Messages

    private func setupDiagnosisMessagesMenuItem() {
        diagnosisMessagesMenuItem.title = "Diagnosis Messages"
        // No image: an icon would indent every title in this menu section
        // (macOS aligns titles per separator-delimited group).
        diagnosisMessagesMenuItem.isHidden = true
        mainMenu.setSubmenu(diagnosisMessagesMenu, for: diagnosisMessagesMenuItem)
        let insertIndex = mainMenu.index(of: activityGraphMenuItem) + 1
        mainMenu.insertItem(diagnosisMessagesMenuItem, at: insertIndex)
    }

    @objc private func handleDiagnosisMessagesUpdated() {
        rebuildDiagnosisMessagesMenu()
    }

    private func rebuildDiagnosisMessagesMenu() {
        let servers = manager.diagnosisMessageMonitor.latest.filter { !$0.messages.isEmpty }
        let count = servers.reduce(0) { $0 + $1.messages.count }

        diagnosisMessagesMenuItem.isHidden = count == 0
        guard count > 0 else { return }

        diagnosisMessagesMenuItem.title = "Diagnosis Messages (\(count))"
        diagnosisMessagesMenu.removeAllItems()

        let showServerNames = servers.count > 1
        let timestampFormatter = RelativeDateTimeFormatter()

        for (index, server) in servers.enumerated() {
            if showServerNames {
                if index > 0 { diagnosisMessagesMenu.addItem(NSMenuItem.separator()) }
                let header = NSMenuItem(title: server.displayName, action: nil, keyEquivalent: "")
                header.isEnabled = false
                diagnosisMessagesMenu.addItem(header)
            }

            for message in server.messages {
                let age = timestampFormatter.localizedString(for: message.timestamp, relativeTo: Date())
                var text = message.plain.replacingOccurrences(of: "\n", with: " ")
                if text.count > 80 {
                    text = String(text.prefix(79)) + "\u{2026}"
                }
                let item = NSMenuItem(title: "\(text)  (\(age))", action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.toolTip = message.plain
                diagnosisMessagesMenu.addItem(item)
            }
        }

        diagnosisMessagesMenu.addItem(NSMenuItem.separator())
        let dismissItem = NSMenuItem(
            title: "Dismiss All",
            action: #selector(dismissAllDiagnosisMessagesAction(_:)),
            keyEquivalent: ""
        )
        dismissItem.target = self
        diagnosisMessagesMenu.addItem(dismissItem)
    }

    @objc private func dismissAllDiagnosisMessagesAction(_: NSMenuItem) {
        manager.diagnosisMessageMonitor.dismissAll()
    }

    // MARK: - Server Updates

    private func setupServerUpdatesMenuItem() {
        serverUpdatesMenuItem.title = "Server Updates"
        // No image: an icon would indent every title in this menu section
        // (macOS aligns titles per separator-delimited group).
        serverUpdatesMenuItem.isHidden = true
        mainMenu.setSubmenu(serverUpdatesMenu, for: serverUpdatesMenuItem)
        // Lives in the manage-servers section, directly above Admin Console.
        let insertIndex = mainMenu.index(of: webAdminMenuItem)
        mainMenu.insertItem(serverUpdatesMenuItem, at: insertIndex)
    }

    @objc private func handleServerUpdatesUpdated() {
        rebuildServerUpdatesMenu()
    }

    private func rebuildServerUpdatesMenu() {
        let servers = manager.serverUpdateMonitor.serversWithUpdates

        serverUpdatesMenuItem.isHidden = servers.isEmpty
        guard !servers.isEmpty else { return }

        serverUpdatesMenuItem.title = "Server Updates (\(servers.count))"
        serverUpdatesMenu.removeAllItems()

        for (index, server) in servers.enumerated() {
            if index > 0 { serverUpdatesMenu.addItem(NSMenuItem.separator()) }
            let header = NSMenuItem(title: server.displayName, action: nil, keyEquivalent: "")
            header.isEnabled = false
            serverUpdatesMenu.addItem(header)

            for update in server.updates {
                let item = NSMenuItem(title: update, action: nil, keyEquivalent: "")
                item.isEnabled = false
                serverUpdatesMenu.addItem(item)
            }

            // AdGuard Home installs its own update via the API; Pi-hole has no
            // update endpoint, so the action opens its web admin instead.
            let action: NSMenuItem
            if server.canSelfUpdate {
                action = NSMenuItem(
                    title: "Update Now",
                    action: #selector(updateServerAction(_:)),
                    keyEquivalent: ""
                )
            } else {
                action = NSMenuItem(
                    title: "Open Web Admin\u{2026}",
                    action: #selector(openWebAdminForUpdateAction(_:)),
                    keyEquivalent: ""
                )
            }
            action.target = self
            action.representedObject = server.identifier
            serverUpdatesMenu.addItem(action)
        }
    }

    @objc private func updateServerAction(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        let monitor = manager.serverUpdateMonitor
        let displayName = monitor.serversWithUpdates
            .first { $0.identifier == identifier }?.displayName ?? identifier

        Task { @MainActor in
            let success = await monitor.beginSelfUpdate(identifier: identifier)
            let alert = NSAlert()
            if success {
                alert.messageText = "Updating \(displayName)"
                alert.informativeText = "AdGuard Home is downloading and installing the update. The server restarts itself when it finishes; it may be briefly unreachable."
            } else {
                alert.alertStyle = .warning
                alert.messageText = "Update Failed to Start"
                alert.informativeText = "\(displayName) did not accept the update request. Check the server's log, or update it from its web admin console."
            }
            alert.runModal()
        }
    }

    @objc private func openWebAdminForUpdateAction(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        launchWebAdmin(for: identifier)
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

        let hasRefreshableBackend = hasV6 || hasAdGuard
        let canSync = v6Count >= 2
        updateGravityMenuItem.isHidden = !hasRefreshableBackend
        updateGravityMenuItem.isEnabled = hasRefreshableBackend && networkOverview.canBeManaged && !isBusy

        syncParentMenuItem.isHidden = !canSync
        syncParentMenuItem.isEnabled = canSync
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
