//
//  SyncSettingsViewController.swift
//  PiGuard
//
//  Created by Codex on 3/12/26.
//

import Cocoa

protocol SyncSettingsViewControllerDelegate: AnyObject {
    func syncSettingsUpdated()
    func syncNowRequestedFromSettings()
}

final class SyncSettingsViewController: NSViewController {
    weak var delegate: SyncSettingsViewControllerDelegate?

    private let syncEnabledCheckbox = NSButton(checkboxWithTitle: "Enable Primary → Secondary Sync", target: nil, action: nil)
    private let setupHelperLabel = SyncSettingsViewController.makeHelperLabel("Choose the source Pi-hole and the destination Pi-hole that should mirror it.")

    private let primaryLabel = NSTextField(labelWithString: "Primary")
    private let primaryPopup = NSPopUpButton()
    private let secondaryLabel = NSTextField(labelWithString: "Secondary")
    private let secondaryPopup = NSPopUpButton()

    private let intervalLabel = NSTextField(labelWithString: "Interval")
    private let intervalPresetPopup = NSPopUpButton()
    private let intervalField = NSTextField()
    private let intervalUnitsLabel = NSTextField(labelWithString: "min")

    private let scopeLabel = NSTextField(labelWithString: "What to sync")
    private let syncGroupsCheckbox = NSButton(checkboxWithTitle: "Groups", target: nil, action: nil)
    private let syncAdlistsCheckbox = NSButton(checkboxWithTitle: "Adlists", target: nil, action: nil)
    private let syncDomainsCheckbox = NSButton(checkboxWithTitle: "Domains", target: nil, action: nil)
    private let dryRunCheckbox = NSButton(checkboxWithTitle: "Preview only (dry run)", target: nil, action: nil)
    private let behaviorHelperLabel = SyncSettingsViewController.makeHelperLabel("Turn off any scope you do not want reconciled. Dry run computes changes without writing to the secondary.")

    private let wipeSecondaryCheckbox = NSButton(checkboxWithTitle: "Wipe secondary adlists before sync", target: nil, action: nil)
    private let safetyHelperLabel = SyncSettingsViewController.makeWarningLabel("Use this only when you want the secondary rebuilt from scratch. Blocking may temporarily drop until gravity finishes.")

    private let summaryLabel = NSTextField(labelWithString: "")
    private let lastSyncLabel = NSTextField(labelWithString: "")
    private let logToggleCheckbox = NSButton(checkboxWithTitle: "Show activity log in separate window", target: nil, action: nil)
    private let logHelperLabel = SyncSettingsViewController.makeHelperLabel("Open the sync log only when you need detailed output. It no longer takes space inside this window.")

    private var activityLogLines: [String] = []
    private var logWindowController: SyncActivityLogWindowController?
    private var isSyncInProgress = false
    private var activeHelpPopover: NSPopover?

    private let syncNowButton = NSButton(title: "Sync Now", target: nil, action: nil)
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)

    private let presetIntervals = [5, 15, 30, 60]
    private let settingLabelWidth: CGFloat = 160
    private let helpPopoverWidth: CGFloat = 280

    private var v6Connections: [PiholeConnectionV4] {
        Preferences.standard.piholes.filter { $0.backendType.supportsSync }
    }

    private var excludedConnectionCount: Int {
        Preferences.standard.piholes.count - v6Connections.count
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 620))
        container.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 3, weight: .semibold)
        summaryLabel.lineBreakMode = .byWordWrapping
        summaryLabel.maximumNumberOfLines = 4

        lastSyncLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        lastSyncLabel.textColor = .secondaryLabelColor
        lastSyncLabel.lineBreakMode = .byWordWrapping
        lastSyncLabel.maximumNumberOfLines = 3

        let headerTitleLabel = NSTextField(labelWithString: "Sync Settings")
        headerTitleLabel.font = NSFont.systemFont(ofSize: 23, weight: .semibold)

        let headerDetailLabel = Self.makeHelperLabel("A simpler setup flow: confirm status first, then choose source, destination, interval, and sync scope.")
        headerDetailLabel.maximumNumberOfLines = 2

        syncEnabledCheckbox.target = self
        syncEnabledCheckbox.action = #selector(syncEnabledChanged)
        primaryPopup.target = self
        primaryPopup.action = #selector(primaryChanged)
        secondaryPopup.target = self
        secondaryPopup.action = #selector(secondaryChanged)
        intervalPresetPopup.target = self
        intervalPresetPopup.action = #selector(intervalPresetChanged)
        intervalField.target = self
        intervalField.action = #selector(intervalChanged)
        syncGroupsCheckbox.target = self
        syncGroupsCheckbox.action = #selector(scopeChanged)
        syncAdlistsCheckbox.target = self
        syncAdlistsCheckbox.action = #selector(scopeChanged)
        syncDomainsCheckbox.target = self
        syncDomainsCheckbox.action = #selector(scopeChanged)
        dryRunCheckbox.target = self
        dryRunCheckbox.action = #selector(dryRunChanged)
        wipeSecondaryCheckbox.target = self
        wipeSecondaryCheckbox.action = #selector(wipeSecondaryChanged)
        logToggleCheckbox.target = self
        logToggleCheckbox.action = #selector(logToggleChanged)
        syncNowButton.target = self
        syncNowButton.action = #selector(syncNowPressed)
        closeButton.target = self
        closeButton.action = #selector(closePressed)

        intervalField.alignment = .right
        intervalField.placeholderString = "Custom"
        intervalField.controlSize = .small
        intervalPresetPopup.controlSize = .small
        primaryPopup.controlSize = .small
        secondaryPopup.controlSize = .small
        syncNowButton.bezelStyle = .rounded
        closeButton.bezelStyle = .rounded
        logToggleCheckbox.setButtonType(.switch)

        intervalPresetPopup.addItems(withTitles: presetIntervals.map { "\($0) min" } + ["Custom"])

        let overviewCard = Self.makeSection(title: "Overview")
        overviewCard.stack.spacing = 12
        overviewCard.stack.addArrangedSubview(summaryLabel)
        overviewCard.stack.addArrangedSubview(lastSyncLabel)
        overviewCard.stack.addArrangedSubview(makeOverviewActionsRow())

        let setupCard = Self.makeSection(title: "Connection Setup")
        setupCard.stack.addArrangedSubview(setupHelperLabel)
        setupCard.stack.addArrangedSubview(
            makeCheckboxRow(
                syncEnabledCheckbox,
                helpText: "Turn this on when you want PiGuard to treat one Pi-hole as the source of truth and continuously reconcile a second Pi-hole to match it."
            )
        )
        setupCard.stack.addArrangedSubview(makeSetupGrid())

        let behaviorCard = Self.makeSection(title: "Sync Behavior")
        behaviorCard.stack.addArrangedSubview(behaviorHelperLabel)
        behaviorCard.stack.addArrangedSubview(makeBehaviorGrid())
        behaviorCard.stack.addArrangedSubview(makeScopeRow())
        behaviorCard.stack.addArrangedSubview(
            makeCheckboxRow(
                dryRunCheckbox,
                helpText: "Dry run shows the planned changes without writing anything to the secondary."
            )
        )

        let safetyCard = Self.makeSection(title: "Safety")
        safetyCard.stack.addArrangedSubview(safetyHelperLabel)
        safetyCard.stack.addArrangedSubview(
            makeCheckboxRow(
                wipeSecondaryCheckbox,
                helpText: "This clears the secondary adlist set before PiGuard rebuilds it from the primary."
            )
        )

        let logCard = Self.makeSection(title: "Activity Log")
        logCard.stack.addArrangedSubview(logHelperLabel)
        logCard.stack.addArrangedSubview(logToggleCheckbox)

        let headerStack = NSStackView(views: [headerTitleLabel, headerDetailLabel])
        headerStack.orientation = .vertical
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView(views: [
            overviewCard.box,
            setupCard.box,
            behaviorCard.box,
            safetyCard.box,
            logCard.box,
        ])
        contentStack.orientation = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let footerLabel = Self.makeHelperLabel("Sync only works between Pi-hole v6 connections. Other backends remain available for monitoring and blocking control.")
        footerLabel.maximumNumberOfLines = 2
        footerLabel.translatesAutoresizingMaskIntoConstraints = false

        let footerButtons = NSStackView(views: [closeButton])
        footerButtons.orientation = .horizontal
        footerButtons.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(headerStack)
        container.addSubview(contentStack)
        container.addSubview(footerLabel)
        container.addSubview(footerButtons)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            contentStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 18),
            contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            overviewCard.box.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            setupCard.box.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            behaviorCard.box.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            safetyCard.box.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            logCard.box.widthAnchor.constraint(equalTo: contentStack.widthAnchor),

            footerLabel.topAnchor.constraint(equalTo: contentStack.bottomAnchor, constant: 16),
            footerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            footerLabel.trailingAnchor.constraint(lessThanOrEqualTo: footerButtons.leadingAnchor, constant: -12),
            footerLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -22),

            footerButtons.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            footerButtons.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sync Settings"
        preferredContentSize = NSSize(width: 760, height: 620)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncProgress(_:)), name: .piGuardSyncProgress, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncBegan), name: .piGuardSyncBegan, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncEnded), name: .piGuardSyncEnded, object: nil)
        refreshUI()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if let window = view.window {
            window.setContentSize(preferredContentSize)
            window.minSize = preferredContentSize
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        logWindowController?.close()
        logWindowController = nil
        logToggleCheckbox.state = .off
    }

    private func makeSetupGrid() -> NSGridView {
        let grid = NSGridView(views: [
            [makeSettingLabelRow(primaryLabel), primaryPopup],
            [makeSettingLabelRow(secondaryLabel), secondaryPopup],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.xPlacement = .fill
        grid.column(at: 0).width = settingLabelWidth
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        return grid
    }

    private func makeBehaviorGrid() -> NSGridView {
        let intervalRow = NSStackView(views: [intervalPresetPopup, intervalField, intervalUnitsLabel])
        intervalRow.orientation = .horizontal
        intervalRow.spacing = 8
        intervalRow.alignment = .centerY
        intervalField.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let grid = NSGridView(views: [[
            makeSettingLabelRow(
                intervalLabel,
                helpText: "This controls how often PiGuard compares the primary and secondary and applies any needed changes."
            ),
            intervalRow,
        ]])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.xPlacement = .fill
        grid.column(at: 0).width = settingLabelWidth
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        return grid
    }

    private func makeScopeRow() -> NSGridView {
        let scopeControls = NSStackView(views: [syncGroupsCheckbox, syncAdlistsCheckbox, syncDomainsCheckbox])
        scopeControls.orientation = .horizontal
        scopeControls.spacing = 14
        scopeControls.alignment = .centerY

        let grid = NSGridView(views: [[
            makeSettingLabelRow(
                scopeLabel,
                helpText: "Turn off any category you want to manage independently on the secondary."
            ),
            scopeControls,
        ]])
        grid.columnSpacing = 12
        grid.xPlacement = .fill
        grid.column(at: 0).width = settingLabelWidth
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        return grid
    }

    private func makeSettingLabelRow(_ label: NSTextField, helpText: String? = nil) -> NSView {
        var views: [NSView] = [label]
        if let helpText {
            views.append(makeHelpButton(text: helpText))
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        return row
    }

    private func makeCheckboxRow(_ checkbox: NSButton, helpText: String? = nil) -> NSView {
        var views: [NSView] = [checkbox]
        if let helpText {
            views.append(makeHelpButton(text: helpText))
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        views.append(spacer)

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    private func makeOverviewActionsRow() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [spacer, syncNowButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeHelpButton(text: String) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(helpButtonPressed(_:)))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "More information")
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.controlSize = .small
        button.toolTip = "More information"
        button.setButtonType(.momentaryPushIn)
        button.identifier = NSUserInterfaceItemIdentifier(text)
        button.widthAnchor.constraint(equalToConstant: 18).isActive = true
        button.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return button
    }

    @objc private func helpButtonPressed(_ sender: NSButton) {
        guard let text = sender.identifier?.rawValue else { return }

        activeHelpPopover?.close()

        let label = Self.makeHelperLabel(text)
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            contentView.widthAnchor.constraint(equalToConstant: helpPopoverWidth),
        ])

        let viewController = NSViewController()
        viewController.view = contentView

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = viewController
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        activeHelpPopover = popover
    }

    private func refreshUI() {
        let hasAtLeastTwo = v6Connections.count >= 2

        syncEnabledCheckbox.state = Preferences.standard.syncEnabled ? .on : .off
        wipeSecondaryCheckbox.state = Preferences.standard.syncWipeSecondaryBeforeSync ? .on : .off
        syncGroupsCheckbox.state = Preferences.standard.syncSkipGroups ? .off : .on
        syncAdlistsCheckbox.state = Preferences.standard.syncSkipAdlists ? .off : .on
        syncDomainsCheckbox.state = Preferences.standard.syncSkipDomains ? .off : .on
        dryRunCheckbox.state = Preferences.standard.syncDryRunEnabled ? .on : .off

        populatePopups()
        applyStoredSelection(to: primaryPopup, identifier: Preferences.standard.syncPrimaryIdentifier)
        applyStoredSelection(to: secondaryPopup, identifier: Preferences.standard.syncSecondaryIdentifier)
        configureIntervalControls()

        let syncEnabled = syncEnabledCheckbox.state == .on
        let controlsEnabled = hasAtLeastTwo && syncEnabled && !isSyncInProgress

        [primaryPopup, secondaryPopup, intervalPresetPopup, intervalField, wipeSecondaryCheckbox, syncGroupsCheckbox, syncAdlistsCheckbox, syncDomainsCheckbox, dryRunCheckbox].forEach {
            $0.isEnabled = controlsEnabled
        }
        syncEnabledCheckbox.isEnabled = hasAtLeastTwo && !isSyncInProgress

        validateSelection()
        updateReadinessSummary()
        updateLastSyncLabel()
        updateLogVisibility()
        syncNowButton.isEnabled = isReadyToSync
    }

    private var isReadyToSync: Bool {
        v6Connections.count >= 2 &&
        syncEnabledCheckbox.state == .on &&
        !isSyncInProgress &&
        !selectedIdentifier(from: primaryPopup).isEmpty &&
        !selectedIdentifier(from: secondaryPopup).isEmpty &&
        selectedIdentifier(from: primaryPopup) != selectedIdentifier(from: secondaryPopup)
    }

    private func updateReadinessSummary() {
        summaryLabel.stringValue = readinessSummaryText()
    }

    private func readinessSummaryText() -> String {
        if isSyncInProgress {
            return "Sync is currently running. PiGuard will re-enable controls when the job completes."
        }

        if v6Connections.count < 2 {
            let count = v6Connections.count
            if count == 0 {
                if excludedConnectionCount > 0 {
                    return "Add two Pi-hole v6 connections to enable sync. AdGuard Home and Pi-hole v5 connections are not eligible."
                }
                return "Add two Pi-hole v6 connections to enable sync."
            }
            if excludedConnectionCount > 0 {
                return "Add one more Pi-hole v6 connection to enable sync. Other configured backends stay available for monitoring and blocking control only."
            }
            return "Add one more Pi-hole v6 connection to enable sync."
        }

        if syncEnabledCheckbox.state != .on {
            return "Sync is off. Turn it on to choose a primary, a secondary, and an interval."
        }

        let primary = selectedIdentifier(from: primaryPopup)
        let secondary = selectedIdentifier(from: secondaryPopup)

        if primary.isEmpty || secondary.isEmpty {
            return "Choose both a primary and a secondary Pi-hole to finish setup."
        }

        if primary == secondary {
            return "Primary and secondary must be different Pi-holes."
        }

        let interval = resolvedIntervalMinutes()
        let dryRunSuffix = dryRunCheckbox.state == .on ? " in dry-run mode" : ""
        return "Ready to sync every \(interval) minutes\(dryRunSuffix)."
    }

    private func updateLastSyncLabel() {
        if let last = Preferences.standard.syncLastRunAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let status = Preferences.standard.syncLastStatus
            let message = Preferences.standard.syncLastMessage
            let statusText = status.isEmpty ? "Last sync" : "Last sync (\(status))"
            let compactMessage = compactLastSyncMessage(message)
            if message.isEmpty {
                lastSyncLabel.stringValue = "\(statusText): \(formatter.string(from: last))"
            } else {
                lastSyncLabel.stringValue = "\(statusText): \(formatter.string(from: last))\n\(compactMessage)"
            }
        } else if isSyncInProgress {
            lastSyncLabel.stringValue = "Current activity: sync in progress."
        } else {
            lastSyncLabel.stringValue = "No sync run yet."
        }
    }

    private func updateLogVisibility() {
        if logToggleCheckbox.state == .on {
            showLogWindow()
        } else {
            logWindowController?.close()
            logWindowController = nil
        }
    }

    private func showLogWindow() {
        if let controller = logWindowController {
            controller.showWindow(self)
            controller.window?.makeKeyAndOrderFront(self)
            controller.replaceLog(with: activityLogLines)
            return
        }

        let controller = SyncActivityLogWindowController()
        controller.onClose = { [weak self] in
            self?.logWindowController = nil
            self?.logToggleCheckbox.state = .off
        }
        controller.replaceLog(with: activityLogLines)
        controller.showWindow(self)
        controller.window?.makeKeyAndOrderFront(self)
        logWindowController = controller
    }

    private func compactLastSyncMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let parts = trimmed
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard parts.count > 1 else {
            return shorten(trimmed, maxLength: 120)
        }

        let compactParts = parts.map { part -> String in
            let cleaned = part.replacingOccurrences(of: "[Dry run] ", with: "Dry run ")
            if cleaned.hasPrefix("Groups:") || cleaned.hasPrefix("Dry run Groups:") {
                return compactSyncSection(cleaned, label: "Groups")
            }
            if cleaned.hasPrefix("Adlists:") || cleaned.hasPrefix("Dry run Adlists:") {
                return compactSyncSection(cleaned, label: "Adlists")
            }
            if cleaned.hasPrefix("Domains") || cleaned.hasPrefix("Dry run Domains") {
                return cleaned.contains("skipped") ? "Domains skipped" : "Domains updated"
            }
            return shorten(cleaned, maxLength: 40)
        }

        return shorten(compactParts.joined(separator: "  •  "), maxLength: 120)
    }

    private func compactSyncSection(_ message: String, label: String) -> String {
        let dryRunPrefix = message.hasPrefix("Dry run ") ? "Dry run " : ""
        let withoutPrefix = dryRunPrefix.isEmpty ? message : String(message.dropFirst("Dry run ".count))
        let summary = withoutPrefix
            .replacingOccurrences(of: "\(label): ", with: "")
            .replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(dryRunPrefix)\(label) \(summary)"
    }

    private func shorten(_ string: String, maxLength: Int) -> String {
        guard string.count > maxLength else { return string }
        return String(string.prefix(maxLength - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func configureIntervalControls() {
        let interval = Preferences.standard.syncIntervalMinutes
        let usesCustom = Preferences.standard.syncIntervalUsesCustom

        if !usesCustom, let presetIndex = presetIntervals.firstIndex(of: interval) {
            intervalPresetPopup.selectItem(at: presetIndex)
            intervalField.isHidden = true
            intervalUnitsLabel.isHidden = true
            intervalField.stringValue = ""
        } else {
            intervalPresetPopup.selectItem(at: presetIntervals.count)
            intervalField.isHidden = false
            intervalUnitsLabel.isHidden = false
            intervalField.stringValue = "\(interval)"
        }
    }

    private func populatePopups() {
        primaryPopup.removeAllItems()
        secondaryPopup.removeAllItems()

        for connection in v6Connections {
            let title = displayTitle(for: connection)
            let identifier = connection.identifier

            [primaryPopup, secondaryPopup].forEach { popup in
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.representedObject = identifier
                item.toolTip = identifier
                popup.menu?.addItem(item)
            }
        }
    }

    private func displayTitle(for connection: PiholeConnectionV4) -> String {
        connection.endpointDisplayName
    }

    private func applyStoredSelection(to popup: NSPopUpButton, identifier: String) {
        guard !identifier.isEmpty else { return }
        for item in popup.itemArray {
            guard let represented = item.representedObject as? String else { continue }
            if represented == identifier {
                popup.select(item)
                return
            }
            if let connection = v6Connections.first(where: { $0.identifier == represented || $0.legacyIdentifier == represented }),
               connection.identifier == represented,
               connection.legacyIdentifier == identifier {
                popup.select(item)
                return
            }
        }
    }

    private func selectedIdentifier(from popup: NSPopUpButton) -> String {
        popup.selectedItem?.representedObject as? String ?? ""
    }

    private func resolvedIntervalMinutes() -> Int {
        let selectedIndex = intervalPresetPopup.indexOfSelectedItem
        if presetIntervals.indices.contains(selectedIndex) {
            return presetIntervals[selectedIndex]
        }

        if let minutes = Int(intervalField.stringValue), minutes >= 5 {
            return minutes
        }

        return Preferences.standard.syncIntervalMinutes
    }

    private func validateSelection() {
        let primary = selectedIdentifier(from: primaryPopup)
        let secondary = selectedIdentifier(from: secondaryPopup)
        guard !primary.isEmpty, primary == secondary, secondaryPopup.numberOfItems > 1 else { return }

        for item in secondaryPopup.itemArray {
            guard let represented = item.representedObject as? String else { continue }
            if represented != primary {
                secondaryPopup.select(item)
                break
            }
        }

        Preferences.standard.set(syncSecondaryIdentifier: selectedIdentifier(from: secondaryPopup))
    }

    @objc private func handleSyncProgress(_ notification: Notification) {
        guard let message = notification.userInfo?[SyncProgress.messageKey] as? String else { return }
        appendLog(message)
    }

    @objc private func handleSyncBegan() {
        isSyncInProgress = true
        appendLog("sync started")
        refreshUI()
    }

    @objc private func handleSyncEnded() {
        isSyncInProgress = false
        appendLog("sync ended")
        refreshUI()
    }

    private func appendLog(_ line: String) {
        activityLogLines.append(line)
        logWindowController?.replaceLog(with: activityLogLines)
    }

    private func clearLog() {
        activityLogLines.removeAll()
        logWindowController?.replaceLog(with: activityLogLines)
    }

    private func persistSelections() {
        Preferences.standard.set(syncEnabled: syncEnabledCheckbox.state == .on)
        Preferences.standard.set(syncWipeSecondaryBeforeSync: wipeSecondaryCheckbox.state == .on)
        Preferences.standard.set(syncSkipGroups: syncGroupsCheckbox.state == .off)
        Preferences.standard.set(syncSkipAdlists: syncAdlistsCheckbox.state == .off)
        Preferences.standard.set(syncSkipDomains: syncDomainsCheckbox.state == .off)
        Preferences.standard.set(syncDryRunEnabled: dryRunCheckbox.state == .on)
        Preferences.standard.set(syncPrimaryIdentifier: selectedIdentifier(from: primaryPopup))
        Preferences.standard.set(syncSecondaryIdentifier: selectedIdentifier(from: secondaryPopup))
        Preferences.standard.set(syncIntervalUsesCustom: intervalPresetPopup.indexOfSelectedItem >= presetIntervals.count)
        Preferences.standard.set(syncIntervalMinutes: max(5, resolvedIntervalMinutes()))
        delegate?.syncSettingsUpdated()
    }

    @objc private func syncEnabledChanged() {
        persistSelections()
        refreshUI()
    }

    @objc private func primaryChanged() {
        persistSelections()
        refreshUI()
    }

    @objc private func secondaryChanged() {
        persistSelections()
        refreshUI()
    }

    @objc private func intervalPresetChanged() {
        if intervalPresetPopup.indexOfSelectedItem < presetIntervals.count {
            intervalField.stringValue = ""
        } else if intervalField.stringValue.isEmpty {
            intervalField.stringValue = "\(max(5, Preferences.standard.syncIntervalMinutes))"
            view.window?.makeFirstResponder(intervalField)
        }
        persistSelections()
        refreshUI()
    }

    @objc private func intervalChanged() {
        persistSelections()
        refreshUI()
    }

    @objc private func scopeChanged() {
        persistSelections()
        refreshUI()
    }

    @objc private func dryRunChanged() {
        persistSelections()
        refreshUI()
    }

    @objc private func wipeSecondaryChanged() {
        if wipeSecondaryCheckbox.state == .on {
            confirmEnableWipe()
        } else {
            persistSelections()
            refreshUI()
        }
    }

    @objc private func logToggleChanged() {
        updateLogVisibility()
    }

    private func confirmEnableWipe() {
        guard let window = view.window else {
            persistSelections()
            refreshUI()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Enable destructive pre-clean?"
        alert.informativeText = "PiGuard will remove or disable adlists on the secondary before rebuilding them from the primary, and gravity may take time to finish afterward."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response != .alertFirstButtonReturn {
                self.wipeSecondaryCheckbox.state = .off
            }
            self.persistSelections()
            self.refreshUI()
        }
    }

    @objc private func syncNowPressed() {
        persistSelections()
        clearLog()
        appendLog("Sync Now: requested")
        delegate?.syncNowRequestedFromSettings()
    }

    @objc private func closePressed() {
        view.window?.close()
    }

    private static func makeSection(title: String) -> (box: NSBox, stack: NSStackView) {
        let box = NSBox()
        box.title = title
        box.titlePosition = .atTop
        box.boxType = .custom
        box.cornerRadius = 10
        box.borderWidth = 1
        box.borderColor = NSColor.separatorColor
        box.fillColor = NSColor.windowBackgroundColor
        box.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView?.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.contentView!.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor, constant: -14),
        ])

        return (box, stack)
    }

    private static func makeHelperLabel(_ string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        return label
    }

    private static func makeWarningLabel(_ string: String) -> NSTextField {
        let label = makeHelperLabel(string)
        label.textColor = .systemOrange
        return label
    }
}

private final class SyncActivityLogWindowController: NSWindowController, NSWindowDelegate {
    private let logTextView = NSTextView()
    var onClose: (() -> Void)?

    init() {
        let viewController = NSViewController()
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false

        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        logTextView.textContainerInset = NSSize(width: 8, height: 8)
        scrollView.documentView = logTextView

        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])

        viewController.view = contentView

        let window = NSWindow(contentViewController: viewController)
        window.title = "Sync Activity Log"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 640, height: 360))
        window.minSize = NSSize(width: 480, height: 240)

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func replaceLog(with lines: [String]) {
        logTextView.string = lines.joined(separator: "\n")
        logTextView.scrollToEndOfDocument(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
