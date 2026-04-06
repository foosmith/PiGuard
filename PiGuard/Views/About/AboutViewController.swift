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

    @IBAction func aboutURLAction(_: NSButton) {
        let url = URL(string: "https://github.com/foosmith/PiGuard")!
        NSWorkspace.shared.open(url)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        versionLabel.stringValue = Self.versionDisplayString()
    }

    private static func versionDisplayString() -> String {
        let infoDictionary = Bundle.main.infoDictionary
        let marketingVersion = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Version \(marketingVersion) (build \(buildNumber))"
    }
}
