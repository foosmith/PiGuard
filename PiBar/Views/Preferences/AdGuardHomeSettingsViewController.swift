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

    @IBOutlet var hostnameTextField: NSTextField!
    @IBOutlet var portTextField: NSTextField!
    @IBOutlet var useSSLCheckbox: NSButton!
    @IBOutlet var usernameTextField: NSTextField!
    @IBOutlet var passwordTextField: NSSecureTextField!
    @IBOutlet var adminURLTextField: NSTextField!
    @IBOutlet var testConnectionLabel: NSTextField!
    @IBOutlet var saveAndCloseButton: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()
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
            adminURLTextField.placeholderString = PiholeConnectionV4.generateAdminPanelURL(
                hostname: "adguard.local",
                port: 3000,
                useSSL: false,
                backendType: .adguardHome
            )
        }
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
                self.testConnectionLabel.stringValue = "Unable to Connect"
                self.saveAndCloseButton.isEnabled = false
            }
        }
    }

    @IBAction func saveAndCloseButtonAction(_: NSButton) {
        delegate?.saveAdGuardHomeConnection(draftConnection(), at: currentIndex)
        dismiss(self)
    }

    private func draftConnection() -> PiholeConnectionV4 {
        let adminURL = adminURLTextField.stringValue.isEmpty
            ? PiholeConnectionV4.generateAdminPanelURL(
                hostname: hostnameTextField.stringValue,
                port: Int(portTextField.stringValue) ?? 3000,
                useSSL: useSSLCheckbox.state == .on,
                backendType: .adguardHome
            )
            : adminURLTextField.stringValue

        return PiholeConnectionV4(
            hostname: hostnameTextField.stringValue,
            port: Int(portTextField.stringValue) ?? 3000,
            useSSL: useSSLCheckbox.state == .on,
            token: passwordTextField.stringValue,
            username: usernameTextField.stringValue,
            passwordProtected: true,
            adminPanelURL: adminURL,
            backendType: .adguardHome
        )
    }
}
