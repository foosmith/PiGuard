//
//  AdGuardHomeSettingsViewController.swift
//  PiBar
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

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "AdGuard Home")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: "Connect to an AdGuard Home admin endpoint.")
        subtitleLabel.textColor = .secondaryLabelColor

        [hostnameTextField, portTextField, usernameTextField, passwordTextField, adminURLTextField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.target = self
            $0.action = #selector(textFieldDidChange)
        }

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

        testConnectionLabel.alignment = .right
        testConnectionLabel.textColor = .secondaryLabelColor

        let formStack = NSStackView(views: [
            labeledRow(label: "Hostname", field: hostnameTextField),
            labeledRow(label: "Port", field: portTextField),
            labeledRow(label: "", field: useSSLCheckbox),
            labeledRow(label: "Username", field: usernameTextField),
            labeledRow(label: "Password", field: passwordTextField),
            labeledRow(label: "Admin URL", field: adminURLTextField)
        ])
        formStack.orientation = .vertical
        formStack.spacing = 12
        formStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [testConnectionButton, testConnectionLabel, NSView(), closeButton, saveAndCloseButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView(views: [titleLabel, subtitleLabel, formStack, buttonRow])
        rootStack.orientation = .vertical
        rootStack.spacing = 16
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            rootStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            rootStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24)
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
        updateAdminURLPlaceholder()
        saveAndCloseButton.isEnabled = false
    }

    @objc private func useSSLChanged() {
        updateDefaultPort()
        updateAdminURLPlaceholder()
        saveAndCloseButton.isEnabled = false
    }

    @IBAction func testConnectionButtonAction(_: NSButton) {
        testConnectionLabel.stringValue = "Testing..."
        let connection = draftConnection()
        let api = AdGuardHomeAPI(connection: connection)

        Task {
            do {
                _ = try await api.testConnection()
                self.testConnectionLabel.stringValue = "Connected"
                self.saveAndCloseButton.isEnabled = true
            } catch {
                Log.error(error)
                self.testConnectionLabel.stringValue = "Unable to Connect"
                self.saveAndCloseButton.isEnabled = false
            }
        }
    }

    @IBAction func saveAndCloseButtonAction(_: NSButton) {
        delegate?.saveAdGuardHomeConnection(draftConnection(), at: currentIndex)
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
        testConnectionLabel.stringValue = ""
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

    private func labeledRow(label: String, field: NSView) -> NSStackView {
        let labelField = NSTextField(labelWithString: label)
        labelField.alignment = .right
        labelField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let row = NSStackView(views: [labelField, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }
}
