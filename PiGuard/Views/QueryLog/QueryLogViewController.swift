//
//  QueryLogViewController.swift
//  PiGuard
//

import Cocoa

final class QueryLogViewController: NSViewController {
    private let piholes: [String: Pihole]
    private var entries: [QueryLogEntry] = []
    private var filteredEntries: [QueryLogEntry] = []
    private let searchField = NSSearchField()
    private var searchText: String = ""
    private var currentSortDescriptors: [NSSortDescriptor] = []

    private let serverFilterPopup = NSPopUpButton()
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")

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
        let toolbar = NSStackView(views: [searchField, serverFilterPopup, NSView(), statusLabel, refreshButton])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false

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
        let contextMenu = NSMenu()
        contextMenu.addItem(NSMenuItem(title: "Allow Domain", action: #selector(allowDomainAction(_:)), keyEquivalent: ""))
        contextMenu.addItem(NSMenuItem(title: "Block Domain", action: #selector(blockDomainAction(_:)), keyEquivalent: ""))
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
                self.applyFilter()
                self.statusLabel.stringValue = "\(self.filteredEntries.count) queries"
                self.refreshButton.isEnabled = true
                self.isLoading = false
            }
        }
    }

    private func applyFilter() {
        let selectedIdentifier = serverFilterPopup.selectedItem?.representedObject as? String

        if let selectedIdentifier {
            filteredEntries = entries.filter { $0.serverIdentifier == selectedIdentifier }
        } else {
            filteredEntries = entries
        }

        // Show/hide server column
        let serverCol = tableView.tableColumns.first { $0.identifier.rawValue == "server" }
        serverCol?.isHidden = selectedIdentifier != nil

        tableView.reloadData()
    }

    @objc private func filterChanged() {
        fetchQueryLog()
    }

    @objc private func refreshAction() {
        fetchQueryLog()
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        // TODO: Implement search filtering in Task 5
    }

    // MARK: - Allow / Block

    @objc private func allowDomainAction(_ sender: NSMenuItem) {
        pushDomainRule(allow: true)
    }

    @objc private func blockDomainAction(_ sender: NSMenuItem) {
        pushDomainRule(allow: false)
    }

    private func pushDomainRule(allow: Bool) {
        let row = tableView.clickedRow
        guard row >= 0, row < filteredEntries.count else { return }
        let entry = filteredEntries[row]
        let domain = entry.domain
        let action = allow ? "Allow" : "Block"

        let targets = determineTargetServers()
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

    private func determineTargetServers() -> [Pihole] {
        var targets: [Pihole] = []

        let v6Servers = piholes.values.filter { $0.backendType == .piholeV6 }
        let v5Servers = piholes.values.filter { $0.backendType == .piholeV5 }
        let adguardServers = piholes.values.filter { $0.backendType == .adguardHome }

        if v6Servers.count >= 2 && Preferences.standard.syncEnabled {
            let primaryId = Preferences.standard.syncPrimaryIdentifier
            if let primary = v6Servers.first(where: { $0.identifier == primaryId }) {
                targets.append(primary)
            } else {
                targets.append(contentsOf: v6Servers)
            }
        } else {
            targets.append(contentsOf: v6Servers)
        }

        targets.append(contentsOf: v5Servers)
        targets.append(contentsOf: adguardServers)

        return targets
    }
}

// MARK: - TableView

extension QueryLogViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEntries.count
    }
}

extension QueryLogViewController: NSTableViewDelegate {
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
