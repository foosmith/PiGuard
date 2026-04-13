//
//  AdGuardHomeSettingsViewController.swift
//  PiGuard
//
//  Created by Codex on 3/31/26.
//

import Cocoa

protocol AdGuardHomeSettingsViewControllerDelegate: AnyObject {
    func saveAdGuardHomeConnection(_ connection: PiholeConnectionV4, at index: Int)
}

final class AdGuardHomeSettingsViewController: NSViewController {
    var connection: PiholeConnectionV4?
    var currentIndex: Int = -1
    weak var delegate: AdGuardHomeSettingsViewControllerDelegate?

    private let hostnameTextField = NSTextField()
    private let portTextField = NSTextField()
    private let useSSLCheckbox = NSButton(checkboxWithTitle: "Use SSL", target: nil, action: nil)
    private let usernameTextField = NSTextField()
    private let passwordTextField = NSSecureTextField()
    private let adminURLTextField = NSTextField()
    private let testConnectionLabel = NSTextField(labelWithString: "")
    private let testConnectionButton = NSButton(title: "Test Connection", target: nil, action: nil)
    private let saveAndCloseButton = NSButton(title: "Save", target: nil, action: nil)
    private let closeButton = NSButton(title: "Cancel", target: nil, action: nil)

    // Maps each help button to the text shown in its popover
    private var helpTexts: [ObjectIdentifier: String] = [:]
    private var helpPopover: NSPopover?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 420))
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "AdGuard Home")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: "Connect to an AdGuard Home admin endpoint.")
        subtitleLabel.textColor = .secondaryLabelColor

        // Make all text fields tall and full-width stretching
        [hostnameTextField, portTextField, usernameTextField, passwordTextField, adminURLTextField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.target = self
            $0.action = #selector(textFieldDidChange)
            $0.heightAnchor.constraint(equalToConstant: 32).isActive = true
            $0.setContentHuggingPriority(.defaultLow, for: .horizontal)
            $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        // Port gets a fixed narrow width; hostname expands to fill the rest
        portTextField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        portTextField.setContentHuggingPriority(.required, for: .horizontal)

        hostnameTextField.placeholderString = "adguard.local"
        portTextField.placeholderString = "3000"
        usernameTextField.placeholderString = "Username"
        passwordTextField.placeholderString = "Password"
        adminURLTextField.placeholderString = defaultAdminURL(hostname: "adguard.local", port: 3000, useSSL: false)

        useSSLCheckbox.target = self
        useSSLCheckbox.action = #selector(useSSLChanged)

        testConnectionButton.target = self
        testConnectionButton.action = #selector(testConnectionButtonAction(_:))
        saveAndCloseButton.target = self
        saveAndCloseButton.action = #selector(saveAndCloseButtonAction(_:))
        closeButton.target = self
        closeButton.action = #selector(closeButtonAction(_:))
        saveAndCloseButton.isEnabled = false

        testConnectionLabel.alignment = .left
        testConnectionLabel.textColor = .secondaryLabelColor
        testConnectionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Hostname + Port side by side, hostname stretches
        let hostPortRow = NSStackView(views: [
            labeledColumn(label: "Hostname", field: hostnameTextField,
                help: "The IP address or domain name of your AdGuard Home server.\n\nExamples:\n• 192.168.1.100\n• adguard.local\n• adguard.example.com"),
            labeledColumn(label: "Port", field: portTextField,
                help: "The port number for the AdGuard Home web interface.\n\nDefaults:\n• 3000 — plain HTTP\n• 443 — HTTPS (when Use SSL is on)\n• 80 — if hosted behind a reverse proxy")
        ])
        hostPortRow.orientation = .horizontal
        hostPortRow.alignment = .bottom
        hostPortRow.spacing = 12
        hostPortRow.distribution = .fill
        hostPortRow.translatesAutoresizingMaskIntoConstraints = false

        let sslHelpBtn = makeHelpButton(
            text: "Enable if AdGuard Home is configured with HTTPS. The port will automatically switch between 3000 and 443 when toggled.\n\nLeave off for standard local network setups without a certificate.")
        let sslRow = NSStackView(views: [useSSLCheckbox, sslHelpBtn])
        sslRow.orientation = .horizontal
        sslRow.alignment = .centerY
        sslRow.spacing = 6

        let usernameCol = labeledColumn(label: "Username", field: usernameTextField)
        let passwordCol = labeledColumn(label: "Password", field: passwordTextField)
        let adminURLCol = labeledColumn(label: "Admin URL", field: adminURLTextField,
            help: "The full URL to the AdGuard Home admin panel. Auto-generated from hostname, port, and SSL settings above.\n\nOverride only if you use a reverse proxy or a non-standard path.\n\nExample: https://adguard.example.com/admin")

        let formStack = NSStackView(views: [
            hostPortRow,
            sslRow,
            usernameCol,
            passwordCol,
            adminURLCol
        ])
        formStack.orientation = .vertical
        formStack.alignment = .leading
        formStack.spacing = 12
        formStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [testConnectionButton, testConnectionLabel, NSView(), closeButton, saveAndCloseButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView(views: [titleLabel, subtitleLabel, formStack, buttonRow])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 16
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            rootStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            rootStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            rootStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),

            // Stretch all full-width rows to fill the available width
            formStack.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            hostPortRow.trailingAnchor.constraint(equalTo: formStack.trailingAnchor),
            usernameCol.trailingAnchor.constraint(equalTo: formStack.trailingAnchor),
            passwordCol.trailingAnchor.constraint(equalTo: formStack.trailingAnchor),
            adminURLCol.trailingAnchor.constraint(equalTo: formStack.trailingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        loadConnection()
    }

    @objc private func textFieldDidChange() {
        clearStatus()
        updateAdminURLPlaceholder()
        saveAndCloseButton.isEnabled = false
    }

    @objc private func useSSLChanged() {
        updateDefaultPort()
        clearStatus()
        updateAdminURLPlaceholder()
        saveAndCloseButton.isEnabled = false
    }

    @IBAction func testConnectionButtonAction(_: NSButton) {
        guard let connection = validatedDraftConnection() else { return }
        testConnectionLabel.stringValue = "Testing..."
        testConnectionLabel.textColor = .secondaryLabelColor
        testConnectionButton.isEnabled = false
        let api = AdGuardHomeAPI(connection: connection)

        Task { [weak self] in
            do {
                _ = try await api.testConnection()
                await MainActor.run {
                    guard let self else { return }
                    self.testConnectionLabel.stringValue = "Connected"
                    self.testConnectionLabel.textColor = .systemGreen
                    self.saveAndCloseButton.isEnabled = true
                    self.testConnectionButton.isEnabled = true
                }
            } catch {
                Log.error(error)
                await MainActor.run {
                    guard let self else { return }
                    self.testConnectionLabel.stringValue = self.connectionErrorMessage(for: error)
                    self.testConnectionLabel.textColor = .systemRed
                    self.saveAndCloseButton.isEnabled = false
                    self.testConnectionButton.isEnabled = true
                }
            }
        }
    }

    @IBAction func saveAndCloseButtonAction(_: NSButton) {
        guard let connection = validatedDraftConnection() else { return }
        delegate?.saveAdGuardHomeConnection(connection, at: currentIndex)
        dismiss(self)
    }

    @IBAction func closeButtonAction(_: NSButton) {
        dismiss(self)
    }

    private func loadConnection() {
        if let connection {
            hostnameTextField.stringValue = connection.hostname
            portTextField.stringValue = "\(connection.port)"
            useSSLCheckbox.state = connection.useSSL ? .on : .off
            usernameTextField.stringValue = connection.username
            passwordTextField.stringValue = connection.token
            adminURLTextField.stringValue = connection.adminPanelURL
        } else {
            hostnameTextField.stringValue = "adguard.local"
            portTextField.stringValue = "3000"
            useSSLCheckbox.state = .off
            usernameTextField.stringValue = ""
            passwordTextField.stringValue = ""
            adminURLTextField.stringValue = ""
        }
        clearStatus()
        updateAdminURLPlaceholder()
    }

    private func updateDefaultPort() {
        if useSSLCheckbox.state == .on, portTextField.stringValue == "3000" {
            portTextField.stringValue = "443"
        } else if useSSLCheckbox.state == .off, portTextField.stringValue == "443" {
            portTextField.stringValue = "3000"
        }
    }

    private func updateAdminURLPlaceholder() {
        adminURLTextField.placeholderString = defaultAdminURL(
            hostname: hostnameTextField.stringValue.isEmpty ? "adguard.local" : hostnameTextField.stringValue,
            port: Int(portTextField.stringValue) ?? (useSSLCheckbox.state == .on ? 443 : 3000),
            useSSL: useSSLCheckbox.state == .on
        )
    }

    private func defaultAdminURL(hostname: String, port: Int, useSSL: Bool) -> String {
        PiholeConnectionV4.generateAdminPanelURL(
            hostname: hostname,
            port: port,
            useSSL: useSSL,
            backendType: .adguardHome
        )
    }

    private func draftConnection() -> PiholeConnectionV4 {
        let hostname = hostnameTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int(portTextField.stringValue) ?? (useSSLCheckbox.state == .on ? 443 : 3000)
        let adminURL = adminURLTextField.stringValue.isEmpty
            ? defaultAdminURL(hostname: hostname, port: port, useSSL: useSSLCheckbox.state == .on)
            : adminURLTextField.stringValue

        return PiholeConnectionV4(
            hostname: hostname,
            port: port,
            useSSL: useSSLCheckbox.state == .on,
            token: passwordTextField.stringValue,
            username: usernameTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            passwordProtected: true,
            adminPanelURL: adminURL,
            backendType: .adguardHome
        )
    }

    private func validatedDraftConnection() -> PiholeConnectionV4? {
        let hostname = hostnameTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = usernameTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordTextField.stringValue
        let port = Int(portTextField.stringValue) ?? -1

        guard !hostname.isEmpty else {
            showValidationError("Enter a hostname first")
            return nil
        }
        guard (1 ... 65535).contains(port) else {
            showValidationError("Enter a valid port")
            return nil
        }
        guard !username.isEmpty else {
            showValidationError("Enter the AdGuard Home username")
            return nil
        }
        guard !password.isEmpty else {
            showValidationError("Enter the AdGuard Home password")
            return nil
        }

        return draftConnection()
    }

    private func clearStatus() {
        testConnectionLabel.stringValue = ""
        testConnectionLabel.textColor = .secondaryLabelColor
        testConnectionButton.isEnabled = true
    }

    private func showValidationError(_ message: String) {
        testConnectionLabel.stringValue = message
        testConnectionLabel.textColor = .systemRed
        saveAndCloseButton.isEnabled = false
    }

    private func connectionErrorMessage(for error: Error) -> String {
        if case let APIError.invalidResponse(statusCode, _) = error {
            switch statusCode {
            case 401:
                return "Authentication failed"
            case 403:
                return "Access denied"
            default:
                return "Server responded with \(statusCode)"
            }
        }
        if case APIError.requestTimedOut = error {
            return "Connection timed out"
        }
        return "Unable to connect"
    }

    private func makeHelpButton(text: String) -> NSButton {
        let btn = NSButton()
        btn.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Help")
        btn.imagePosition = .imageOnly
        btn.isBordered = false
        btn.contentTintColor = .tertiaryLabelColor
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.target = self
        btn.action = #selector(helpButtonClicked(_:))
        helpTexts[ObjectIdentifier(btn)] = text
        return btn
    }

    @objc private func helpButtonClicked(_ sender: NSButton) {
        guard let text = helpTexts[ObjectIdentifier(sender)] else { return }

        helpPopover?.close()

        let label = NSTextField(wrappingLabelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.preferredMaxLayoutWidth = 260

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            contentView.widthAnchor.constraint(equalToConstant: 284),
        ])

        let vc = NSViewController()
        vc.view = contentView
        vc.preferredContentSize = contentView.fittingSize

        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        helpPopover = popover
    }

    private func labeledColumn(label: String, field: NSView, help: String? = nil) -> NSStackView {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        labelField.textColor = .secondaryLabelColor
        labelField.translatesAutoresizingMaskIntoConstraints = false

        let labelRow: NSView
        if let help {
            let helpBtn = makeHelpButton(text: help)
            let row = NSStackView(views: [labelField, helpBtn])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 4
            row.translatesAutoresizingMaskIntoConstraints = false
            labelRow = row
        } else {
            labelRow = labelField
        }

        // Field should fill the column's full width
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let col = NSStackView(views: [labelRow, field])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 4
        col.translatesAutoresizingMaskIntoConstraints = false

        // Pin field trailing to column trailing so it stretches
        NSLayoutConstraint.activate([
            field.trailingAnchor.constraint(equalTo: col.trailingAnchor),
            labelRow.trailingAnchor.constraint(lessThanOrEqualTo: col.trailingAnchor),
        ])

        return col
    }
}
