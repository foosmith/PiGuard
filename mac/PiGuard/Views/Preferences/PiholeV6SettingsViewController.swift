//
//  PiholeV6SettingsViewController.swift
//  PiGuard
//
//  Created by Brad Root on 3/16/25.
//  Copyright © 2025 Brad Root. All rights reserved.
//

import Cocoa

protocol PiholeV6SettingsViewControllerDelegate: AnyObject {
    func savePiholeV4Connection(_ connection: PiholeConnectionV4, at index: Int)
}

class PiholeV6SettingsViewController: NSViewController {
    var connection: PiholeConnectionV4?
    var currentIndex: Int = -1
    weak var delegate: PiholeV6SettingsViewControllerDelegate?

    var passwordProtected: Bool = true

    // MARK: - Outlets

    @IBOutlet var hostnameTextField: NSTextField!
    @IBOutlet var portTextField: NSTextField!
    @IBOutlet var useSSLCheckbox: NSButton!

    @IBOutlet var adminURLTextField: NSTextField!


    @IBOutlet weak var totpTextField: NSTextField!
    @IBOutlet weak var passwordTextField: NSSecureTextField!
    @IBOutlet var testConnectionLabel: NSTextField!
    @IBOutlet var saveAndCloseButton: NSButton!
    @IBOutlet var closeButton: NSButton!

    // MARK: - Actions

    @IBAction func textFieldDidChangeAction(_: NSTextField) {
        updateAdminURLPlaceholder()
        saveAndCloseButton.isEnabled = false
    }

    @IBAction func useSSLCheckboxAction(_: NSButton) {
        sslFailSafe()
        updateAdminURLPlaceholder()
        saveAndCloseButton.isEnabled = false
    }

    @IBAction func authenticateRequestAction(_ sender: NSButton) {
        let password = passwordTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.debug("Validating Pi-hole app password...")

        testConnectionLabel.stringValue = "Validating..."

        let connection = PiholeConnectionV4(
            hostname: hostnameTextField.stringValue,
            port: Int(portTextField.stringValue) ?? 80,
            useSSL: useSSLCheckbox.state == .on ? true : false,
            token: password,
            username: "",
            passwordProtected: !password.isEmpty,
            adminPanelURL: "",
            backendType: .piholeV6
        )

        let api = Pihole6API(connection: connection)
        
        Task {
            do {
                if password.isEmpty {
                    _ = try await api.fetchSummary()
                    self.passwordProtected = false
                    self.testConnectionLabel.stringValue = "Connected"
                    self.saveAndCloseButton.isEnabled = true
                } else {
                    let result = try await api.checkPassword(password: password, totp: nil)
                    if result.session.valid {
                        self.passwordProtected = true
                        self.testConnectionLabel.stringValue = "Connected"
                        self.saveAndCloseButton.isEnabled = true
                    } else {
                        self.testConnectionLabel.stringValue = "Invalid app password"
                        self.saveAndCloseButton.isEnabled = false
                    }
                }
            } catch {
                Log.error(error)
                self.testConnectionLabel.stringValue = "Error"
                self.saveAndCloseButton.isEnabled = false
            }
        }
        
    }
    
    @IBAction func testConnectionButtonAction(_: NSButton) {
        testConnection()
    }

    @IBAction func saveAndCloseButtonAction(_: NSButton) {
        var adminPanelURL = adminURLTextField.stringValue
        if adminPanelURL.isEmpty {
            adminPanelURL = PiholeConnectionV4.generateAdminPanelURL(
                hostname: hostnameTextField.stringValue,
                port: Int(portTextField.stringValue) ?? 80,
                useSSL: useSSLCheckbox.state == .on ? true : false,
                backendType: .piholeV6
            )
        }
        delegate?.savePiholeV4Connection(PiholeConnectionV4(
            hostname: hostnameTextField.stringValue,
            port: Int(portTextField.stringValue) ?? 80,
            useSSL: useSSLCheckbox.state == .on ? true : false,
            token: passwordTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            username: "",
            passwordProtected: !passwordTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            adminPanelURL: adminPanelURL,
            backendType: .piholeV6
        ), at: currentIndex)
        dismiss(self)
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        adminURLTextField.toolTip = "Only fill this in if you have a custom Admin panel URL you'd like to use instead of the default shown here."
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        loadPiholeConnection()
    }

    func loadPiholeConnection() {
        Log.debug("Loading Pi-hole at index \(currentIndex)")
        if let connection = connection {
            hostnameTextField.stringValue = connection.hostname
            portTextField.stringValue = "\(connection.port)"
            useSSLCheckbox.state = connection.useSSL ? .on : .off
            passwordTextField.stringValue = connection.token
            adminURLTextField.stringValue = connection.adminPanelURL
            passwordProtected = connection.passwordProtected
        } else {
            hostnameTextField.stringValue = "pi.hole"
            portTextField.stringValue = "80"
            useSSLCheckbox.state = .off
            passwordTextField.stringValue = ""
            adminURLTextField.stringValue = ""
            adminURLTextField.placeholderString = PiholeConnectionV4.generateAdminPanelURL(
                hostname: "pi.hole",
                port: 80,
                useSSL: false,
                backendType: .piholeV6
            )
        }
        testConnectionLabel.stringValue = ""
        saveAndCloseButton.isEnabled = false
    }

    // MARK: - Functions

    fileprivate func sslFailSafe() {
        let useSSL = useSSLCheckbox.state == .on ? true : false

        var port = portTextField.stringValue
        if useSSL, port == "80" {
            port = "443"
        } else if !useSSL, port == "443" {
            port = "80"
        }
        portTextField.stringValue = port
    }

    private func updateAdminURLPlaceholder() {
        let adminURLString = PiholeConnectionV4.generateAdminPanelURL(
            hostname: hostnameTextField.stringValue,
            port: Int(portTextField.stringValue) ?? 80,
            useSSL: useSSLCheckbox.state == .on ? true : false,
            backendType: .piholeV6
        )
        adminURLTextField.placeholderString = "\(adminURLString)"
    }

    func testConnection() {
        Log.debug("Testing connection...")

        testConnectionLabel.stringValue = "Testing... Please wait..."

        let connection = PiholeConnectionV4(
            hostname: hostnameTextField.stringValue,
            port: Int(portTextField.stringValue) ?? 80,
            useSSL: useSSLCheckbox.state == .on ? true : false,
            token: passwordTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            username: "",
            passwordProtected: !passwordTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            adminPanelURL: "",
            backendType: .piholeV6
        )
        let api = Pihole6API(connection: connection)

        Task {
            do {
                _ = try await api.fetchSummary()
                self.passwordProtected = connection.passwordProtected
                self.testConnectionLabel.stringValue = "Success"
                self.saveAndCloseButton.isEnabled = true
            } catch {
                Log.error(error)
                self.testConnectionLabel.stringValue = "Unable to Connect"
                self.saveAndCloseButton.isEnabled = false
            }
        }
    }
}
