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
