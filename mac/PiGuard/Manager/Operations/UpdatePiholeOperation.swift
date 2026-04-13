//
//  UpdatePiholeOperation.swift
//  PiGuard
//
//  Created by Brad Root on 5/26/20.
//  Copyright © 2020 Brad Root. All rights reserved.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation

final class UpdatePiholeOperation: AsyncOperation, @unchecked Sendable {
    private(set) var pihole: Pihole

    init(_ pihole: Pihole) {
        self.pihole = pihole
    }

    override func main() {
        guard let api = pihole.api else {
            state = .isFinished
            return
        }
        Log.debug("Updating Pi-hole: \(pihole.identifier)")
        api.fetchSummary { summary in
            Log.debug("Received Summary for \(self.pihole.identifier)")
            var enabled: Bool? = true
            var online = true
            var canBeManaged: Bool = false

            if let summary = summary {
                if summary.status != "enabled" {
                    enabled = false
                }
                if !api.connection.token.isEmpty || !api.connection.passwordProtected {
                    canBeManaged = true
                }
            } else {
                enabled = nil
                online = false
                canBeManaged = false
            }

            let updatedPihole: Pihole = Pihole(
                api: api,
                api6: nil,
                apiAdguard: nil,
                identifier: api.identifier,
                online: online,
                summary: summary,
                canBeManaged: canBeManaged,
                enabled: enabled,
                backendType: .piholeV5
            )

            self.pihole = updatedPihole

            self.state = .isFinished
        }
    }
}
