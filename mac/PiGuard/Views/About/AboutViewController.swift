//
//  AboutViewController.swift
//  PiGuard
//
//  Created by Brad Root on 5/26/20.
//  Copyright © 2020 Brad Root. All rights reserved.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Cocoa

class AboutViewController: NSViewController {
    @IBOutlet private weak var versionLabel: NSTextField!
    @IBOutlet private weak var copyrightLabel: NSTextField!
    @IBOutlet private weak var githubButton: NSButton!

    @IBAction func aboutURLAction(_: NSButton) {
        let url = URL(string: "https://github.com/foosmith/PiGuard")!
        NSWorkspace.shared.open(url)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        versionLabel.stringValue = Self.versionDisplayString()

        #if !APPSTORE
        // Sparkle-updated builds offer the update check here; the menu bar
        // stays free of app housekeeping. App Store builds update via the
        // store, so they get no button. The About layout is a fully pinned
        // vertical chain (name → version → GitHub link → copyright), so the
        // button is spliced in right below the version line: the GitHub
        // link's top is re-anchored to the button, and autolayout grows the
        // window to fit.
        guard let container = versionLabel.superview else { return }
        if let githubTopPin = container.constraints.first(where: {
            ($0.firstItem as? NSView) === githubButton && $0.firstAttribute == .top
        }) {
            githubTopPin.isActive = false
        }

        let updateButton = NSButton(
            title: "Check for Updates\u{2026}",
            target: self,
            action: #selector(checkForUpdatesAction(_:))
        )
        updateButton.bezelStyle = .rounded
        updateButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(updateButton)
        NSLayoutConstraint.activate([
            updateButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            updateButton.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 10),
            githubButton.topAnchor.constraint(equalTo: updateButton.bottomAnchor, constant: 2),
        ])
        #endif
    }

    #if !APPSTORE
    @objc private func checkForUpdatesAction(_: NSButton) {
        UpdateManager.shared.checkForUpdates()
    }
    #endif

    private static func versionDisplayString() -> String {
        let infoDictionary = Bundle.main.infoDictionary
        let marketingVersion = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Version \(marketingVersion) (build \(buildNumber))"
    }
}
