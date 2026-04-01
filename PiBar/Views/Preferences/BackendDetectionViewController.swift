//
//  BackendDetectionViewController.swift
//  PiBar
//
//  Created by Codex on 3/31/26.
//

import Cocoa

protocol BackendDetectionViewControllerDelegate: AnyObject {
    func backendDetectionViewController(
        _ controller: BackendDetectionViewController,
        didDetect result: BackendDetectionResult,
        draftConnection: PiholeConnectionV4
    )
}

final class BackendDetectionViewController: NSViewController {
    weak var delegate: BackendDetectionViewControllerDelegate?

    private let hostnameTextField = NSTextField()
    private let portTextField = NSTextField()
    private let useSSLCheckbox = NSButton(checkboxWithTitle: "Use SSL", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let detectButton = NSButton(title: "Detect", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 220))
        let titleLabel = NSTextField(labelWithString: "Detect Server Type")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: "Enter the server address and let PiGuard identify the backend.")
        subtitleLabel.textColor = .secondaryLabelColor

        hostnameTextField.placeholderString = "pi.hole"
        hostnameTextField.target = self
        hostnameTextField.action = #selector(inputChanged)
        portTextField.placeholderString = "80"
        portTextField.target = self
        portTextField.action = #selector(inputChanged)

        useSSLCheckbox.target = self
        useSSLCheckbox.action = #selector(useSSLChanged)

        detectButton.target = self
        detectButton.action = #selector(detectButtonAction(_:))
        cancelButton.target = self
        cancelButton.action = #selector(cancelButtonAction(_:))

        let formStack = NSStackView(views: [
            labeledRow(label: "Hostname", field: hostnameTextField),
            labeledRow(label: "Port", field: portTextField),
            labeledRow(label: "", field: useSSLCheckbox)
        ])
        formStack.orientation = .vertical
        formStack.spacing = 12

        statusLabel.textColor = .secondaryLabelColor

        let buttonRow = NSStackView(views: [statusLabel, NSView(), cancelButton, detectButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10

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
        hostnameTextField.stringValue = "pi.hole"
        portTextField.stringValue = "80"
        useSSLCheckbox.state = .off
    }

    @objc private func inputChanged() {
        statusLabel.stringValue = ""
    }

    @objc private func useSSLChanged() {
        if useSSLCheckbox.state == .on, portTextField.stringValue == "80" {
            portTextField.stringValue = "443"
        } else if useSSLCheckbox.state == .off, portTextField.stringValue == "443" {
            portTextField.stringValue = "80"
        }
        statusLabel.stringValue = ""
    }

    @IBAction private func detectButtonAction(_: NSButton) {
        let hostname = hostnameTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let useSSL = useSSLCheckbox.state == .on
        let fallbackPort = useSSL ? 443 : 80
        let port = Int(portTextField.stringValue) ?? fallbackPort

        guard !hostname.isEmpty else {
            statusLabel.stringValue = "Enter a hostname first"
            return
        }

        statusLabel.stringValue = "Detecting..."
        detectButton.isEnabled = false

        Task {
            let result = await BackendDetector.detect(hostname: hostname, port: port, useSSL: useSSL)
            self.detectButton.isEnabled = true

            guard let result else {
                self.statusLabel.stringValue = "Detection failed. Select manually."
                return
            }

            self.statusLabel.stringValue = result.displayString
            self.delegate?.backendDetectionViewController(self, didDetect: result, draftConnection: self.draftConnection(for: result.backendType, hostname: hostname, port: port, useSSL: useSSL))
            self.dismiss(self)
        }
    }

    @IBAction private func cancelButtonAction(_: NSButton) {
        dismiss(self)
    }

    private func draftConnection(for backendType: BackendType, hostname: String, port: Int, useSSL: Bool) -> PiholeConnectionV4 {
        let defaultPort = backendType == .adguardHome ? (useSSL ? 443 : 3000) : (useSSL ? 443 : 80)
        let resolvedPort = portTextField.stringValue.isEmpty ? defaultPort : port

        return PiholeConnectionV4(
            hostname: hostname,
            port: resolvedPort,
            useSSL: useSSL,
            token: "",
            username: "",
            passwordProtected: backendType != .piholeV5,
            adminPanelURL: PiholeConnectionV4.generateAdminPanelURL(
                hostname: hostname,
                port: resolvedPort,
                useSSL: useSSL,
                backendType: backendType
            ),
            backendType: backendType
        )
    }

    private func labeledRow(label: String, field: NSView) -> NSStackView {
        let labelField = NSTextField(labelWithString: label)
        labelField.alignment = .right
        labelField.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let row = NSStackView(views: [labelField, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }
}
