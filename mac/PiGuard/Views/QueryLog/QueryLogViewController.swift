//
//  QueryLogViewController.swift
//  PiGuard
//

import Cocoa

final class QueryLogViewController: NSViewController {
    private let piholes: [String: Pihole]
    private var entries: [QueryLogEntry] = []
    private var filteredEntries: [QueryLogEntry] = []
    private var contextMenuEntry: QueryLogEntry?
    private let searchField = NSSearchField()
    private var searchText: String = ""
    private var currentSortDescriptors: [NSSortDescriptor] = []

    private let serverFilterPopup = NSPopUpButton()
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Allow Domain", action: #selector(allowDomainAction(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Block Domain", action: #selector(blockDomainAction(_:)), keyEquivalent: ""))
        return menu
    }()

    private var isLoading = false

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init(piholes: [String: Pihole]) {
        self.piholes = piholes
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))

        // Server filter
        serverFilterPopup.removeAllItems()
        serverFilterPopup.addItem(withTitle: "All Servers")
        let sortedPiholes = piholes.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        for pihole in sortedPiholes {
            serverFilterPopup.addItem(withTitle: pihole.displayName)
            serverFilterPopup.lastItem?.representedObject = pihole.identifier
        }
        serverFilterPopup.target = self
        serverFilterPopup.action = #selector(filterChanged)

        refreshButton.target = self
        refreshButton.action = #selector(refreshAction)
        refreshButton.bezelStyle = .rounded

        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.placeholderString = "Search"

        statusLabel.textColor = .secondaryLabelColor

        // Toolbar row
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        // Compress spacer before any other view — it absorbs all slack first.
        // Raw value 50 is the "fitting size" compression level (AppKit has no named constant for it).
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(rawValue: 50), for: .horizontal)
        let toolbar = NSStackView(views: [searchField, serverFilterPopup, spacer, statusLabel, refreshButton])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        // Hard floor on the search field — prevents NSStackView from compressing
        // it during any layout pass triggered before or after the window appears
        // (e.g. when the app is activated from the widget and a second AppKit
        // layout pass fires after showWindow returns).
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        // Table
        let timeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
        timeCol.title = "Time"
        timeCol.width = 140
        let domainCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("domain"))
        domainCol.title = "Domain"
        domainCol.width = 250
        let clientCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("client"))
        clientCol.title = "Client"
        clientCol.width = 120
        let statusCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusCol.title = "Status"
        statusCol.width = 80
        let serverCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("server"))
        serverCol.title = "Server"
        serverCol.width = 150

        domainCol.sortDescriptorPrototype = NSSortDescriptor(key: "domain", ascending: true, selector: nil)
        clientCol.sortDescriptorPrototype = NSSortDescriptor(key: "client", ascending: true, selector: nil)
        statusCol.sortDescriptorPrototype = NSSortDescriptor(key: "status", ascending: true, selector: nil)

        tableView.addTableColumn(timeCol)
        tableView.addTableColumn(domainCol)
        tableView.addTableColumn(clientCol)
        tableView.addTableColumn(statusCol)
        tableView.addTableColumn(serverCol)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        // Context menu
        tableView.menu = contextMenu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(toolbar)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        fetchQueryLog()
    }

    // MARK: - Fetching

    private func fetchQueryLog() {
        guard !isLoading else { return }
        isLoading = true
        statusLabel.stringValue = "Loading..."
        refreshButton.isEnabled = false

        let selectedIdentifier = serverFilterPopup.selectedItem?.representedObject as? String

        Task {
            var allEntries: [QueryLogEntry] = []
            for pihole in piholes.values {
                if let selectedIdentifier, pihole.identifier != selectedIdentifier { continue }
                if let api = pihole.api {
                    allEntries.append(contentsOf: await api.fetchQueryLog())
                } else if let api6 = pihole.api6 {
                    allEntries.append(contentsOf: await api6.fetchQueryLog())
                } else if let apiAdguard = pihole.apiAdguard {
                    allEntries.append(contentsOf: await apiAdguard.fetchQueryLog())
                }
            }

            allEntries.sort { $0.timestamp > $1.timestamp }

            await MainActor.run {
                self.entries = allEntries
                self.searchText = ""
                self.searchField.stringValue = ""
                self.currentSortDescriptors = []
                self.tableView.sortDescriptors = []
                self.applyFilter()
                self.refreshButton.isEnabled = true
                self.isLoading = false
            }
        }
    }

    private func applyFilter() {
        let selectedIdentifier = serverFilterPopup.selectedItem?.representedObject as? String

        // Step 1: filter by server
        var result: [QueryLogEntry]
        if let selectedIdentifier {
            result = entries.filter { $0.serverIdentifier == selectedIdentifier }
        } else {
            result = entries
        }

        // Step 2: filter by search text
        if !searchText.isEmpty {
            result = result.filter { entry in
                entry.domain.localizedCaseInsensitiveContains(searchText) ||
                entry.client.localizedCaseInsensitiveContains(searchText) ||
                entry.status.rawValue.localizedCaseInsensitiveContains(searchText) ||
                entry.serverDisplayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Step 3: sort (first descriptor only; switch on key to avoid KVC on Swift struct)
        if let descriptor = currentSortDescriptors.first {
            result.sort { a, b in
                let ascending: Bool
                switch descriptor.key {
                case "domain":
                    ascending = a.domain.localizedCaseInsensitiveCompare(b.domain) == .orderedAscending
                case "client":
                    ascending = a.client.localizedCaseInsensitiveCompare(b.client) == .orderedAscending
                case "status":
                    ascending = a.status.rawValue < b.status.rawValue
                default:
                    ascending = false
                }
                return descriptor.ascending ? ascending : !ascending
            }
        }

        filteredEntries = result

        // Show/hide server column
        let serverCol = tableView.tableColumns.first { $0.identifier.rawValue == "server" }
        serverCol?.isHidden = selectedIdentifier != nil

        tableView.reloadData()
        statusLabel.stringValue = "\(filteredEntries.count) queries"
    }

    @objc private func filterChanged() {
        fetchQueryLog()
    }

    @objc private func refreshAction() {
        fetchQueryLog()
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        searchText = sender.stringValue
        applyFilter()
    }

    // MARK: - Allow / Block

    @objc private func allowDomainAction(_ sender: NSMenuItem) {
        pushDomainRule(allow: true, sender: sender)
    }

    @objc private func blockDomainAction(_ sender: NSMenuItem) {
        pushDomainRule(allow: false, sender: sender)
    }

    private func pushDomainRule(allow: Bool, sender: NSMenuItem) {
        guard let entry = selectedEntryForRuleAction(sender: sender) else { return }
        guard let domain = normalizedRuleDomain(from: entry.domain) else {
            statusLabel.stringValue = "Invalid domain"
            return
        }
        let action = allow ? "Allow" : "Block"

        let targets = determineTargetServers(for: entry)
        guard !targets.isEmpty else {
            statusLabel.stringValue = "Server unavailable"
            return
        }
        Log.debug("Query Log \(action) request for domain \(domain) on server \(entry.serverIdentifier)")
        let serverNames = targets.map { $0.displayName }.joined(separator: ", ")

        let alert = NSAlert()
        alert.messageText = "\(action) \(domain)?"
        alert.informativeText = "This will be applied to: \(serverNames)"
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        statusLabel.stringValue = "Applying..."

        Task {
            var results: [(String, Bool)] = []

            for pihole in targets {
                let success: Bool
                if let api = pihole.api {
                    success = allow ? await api.allowDomain(domain) : await api.blockDomain(domain)
                } else if let api6 = pihole.api6 {
                    success = allow ? await api6.allowDomain(domain) : await api6.blockDomain(domain)
                } else if let apiAdguard = pihole.apiAdguard {
                    success = allow ? await apiAdguard.allowDomain(domain) : await apiAdguard.blockDomain(domain)
                } else {
                    success = false
                }
                results.append((pihole.displayName, success))
            }

            await MainActor.run {
                let failures = results.filter { !$0.1 }
                if failures.isEmpty {
                    self.statusLabel.stringValue = "\(action)ed \(domain)"
                } else {
                    let failedNames = failures.map { $0.0 }.joined(separator: ", ")
                    self.statusLabel.stringValue = "Failed on: \(failedNames)"
                }
            }
        }
    }

    private func normalizedRuleDomain(from rawDomain: String) -> String? {
        let trimmed = rawDomain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func selectedEntryForRuleAction(sender: NSMenuItem) -> QueryLogEntry? {
        if let representedEntry = sender.representedObject as? QueryLogEntry {
            Log.debug("Query Log action using sender.representedObject domain \(representedEntry.domain) server \(representedEntry.serverIdentifier)")
            return representedEntry
        }
        if let contextMenuEntry {
            Log.debug("Query Log action using contextMenuEntry domain \(contextMenuEntry.domain) server \(contextMenuEntry.serverIdentifier)")
            return contextMenuEntry
        }
        let candidateRows = [contextMenuRow(), tableView.clickedRow, tableView.selectedRow]
        for row in candidateRows where row >= 0 && row < filteredEntries.count {
            Log.debug("Query Log action falling back to row \(row) domain \(filteredEntries[row].domain) server \(filteredEntries[row].serverIdentifier)")
            return filteredEntries[row]
        }
        return nil
    }

    private func determineTargetServers(for entry: QueryLogEntry) -> [Pihole] {
        if let pihole = piholes[entry.serverIdentifier] {
            return [pihole]
        }
        return []
    }

    private func contextMenuRow() -> Int {
        guard let window = tableView.window else { return -1 }
        let mouseLocationInWindow = window.mouseLocationOutsideOfEventStream
        let mouseLocationInTable = tableView.convert(mouseLocationInWindow, from: nil)
        return tableView.row(at: mouseLocationInTable)
    }
}

// MARK: - TableView

extension QueryLogViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEntries.count
    }
}

extension QueryLogViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        currentSortDescriptors = tableView.sortDescriptors
        applyFilter()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredEntries.count, let column = tableColumn else { return nil }
        let entry = filteredEntries[row]

        let cellId = NSUserInterfaceItemIdentifier("QueryLogCell")
        let cell: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: cellId, owner: self) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField
            cell.identifier = cellId
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        // Reset color for reused cells
        cell.textField?.textColor = .labelColor

        switch column.identifier.rawValue {
        case "time":
            cell.textField?.stringValue = timeFormatter.string(from: entry.timestamp)
        case "domain":
            cell.textField?.stringValue = entry.domain
        case "client":
            cell.textField?.stringValue = entry.client
        case "status":
            cell.textField?.stringValue = entry.status.rawValue
            cell.textField?.textColor = entry.status == .blocked ? .systemRed : .labelColor
        case "server":
            cell.textField?.stringValue = entry.serverDisplayName
        default:
            break
        }

        return cell
    }
}

extension QueryLogViewController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === contextMenu else { return }

        contextMenuEntry = nil

        let candidateRows = [contextMenuRow(), tableView.clickedRow, tableView.selectedRow]
        for row in candidateRows where row >= 0 && row < filteredEntries.count {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            contextMenuEntry = filteredEntries[row]
            Log.debug("Query Log context menu resolved row \(row) domain \(filteredEntries[row].domain) server \(filteredEntries[row].serverIdentifier)")
            break
        }

        let isEnabled = contextMenuEntry != nil
        for item in menu.items {
            item.target = self
            item.isEnabled = isEnabled
            item.representedObject = contextMenuEntry
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === contextMenu else { return }
    }
}
