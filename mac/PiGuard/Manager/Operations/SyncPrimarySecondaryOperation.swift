//
//  SyncPrimarySecondaryOperation.swift
//  PiGuard
//
//  Full Primary → Secondary sync covering Phase 3 (adlists), Phase 4 (domains),
//  and Phase 5 (groups + group ID translation for adlists/domains).
//
//  Sync order: groups first (so secondary group IDs are available for translation),
//  then adlists, then each domain bucket.
//
//  Respects preferences:
//  - syncDryRunEnabled  — compute diffs but skip all writes
//  - syncSkipGroups     — fetch groups for ID translation but skip group writes
//  - syncSkipAdlists    — skip adlist sync entirely
//  - syncSkipDomains    — skip domain sync entirely
//

import Foundation

final class SyncPrimarySecondaryOperation: AsyncOperation, @unchecked Sendable {

    override func main() {
        Task { [weak self] in
            guard let self else { return }
            defer { self.state = .isFinished }

            let isDryRun = Preferences.standard.syncDryRunEnabled
            let skipGroups = Preferences.standard.syncSkipGroups
            let skipAdlists = Preferences.standard.syncSkipAdlists
            let skipDomains = Preferences.standard.syncSkipDomains

            let modeTag = isDryRun ? " [dry run]" : ""
            SyncProgress.report("Sync\(modeTag): starting…")

            guard Preferences.standard.syncEnabled else {
                self.record(status: .skipped, message: "Sync is turned off.")
                SyncProgress.report("Sync: skipped — sync is turned off.")
                return
            }

            let primaryId = Preferences.standard.syncPrimaryIdentifier
            let secondaryId = Preferences.standard.syncSecondaryIdentifier
            guard !primaryId.isEmpty, !secondaryId.isEmpty, primaryId != secondaryId else {
                self.record(status: .skipped, message: "Primary and Secondary must be different Pi-holes.")
                SyncProgress.report("Sync: skipped — Primary and Secondary must be different Pi-holes.")
                return
            }

            let syncableConnections = Preferences.standard.piholes.filter { $0.backendType.supportsSync }
            let connections = syncableConnections.filter { $0.isEnabled }
            guard
                let primaryConnection = connections.first(where: { $0.identifier == primaryId || $0.legacyIdentifier == primaryId }),
                let secondaryConnection = connections.first(where: { $0.identifier == secondaryId || $0.legacyIdentifier == secondaryId })
            else {
                let selectedButDisabled = syncableConnections.contains {
                    !$0.isEnabled && [$0.identifier, $0.legacyIdentifier].contains(where: { $0 == primaryId || $0 == secondaryId })
                }
                if selectedButDisabled {
                    self.record(status: .skipped, message: "A selected Pi-hole is disabled in Preferences. Re-enable it or choose another server.")
                    SyncProgress.report("Sync: skipped — a selected Pi-hole is disabled in Preferences. Re-enable it or choose another server.")
                } else {
                    self.record(status: .failed, message: "The selected Pi-holes are no longer configured. Re-select them in Sync settings.")
                    SyncProgress.report("Sync: failed — the selected Pi-holes are no longer configured. Re-select them in Sync settings.")
                }
                return
            }

            if primaryConnection.passwordProtected, primaryConnection.token.isEmpty {
                self.record(status: .failed, message: "The Primary Pi-hole is signed out. Re-authenticate it in Preferences.")
                SyncProgress.report("Sync: failed — the Primary Pi-hole is signed out. Re-authenticate it in Preferences.")
                return
            }
            if secondaryConnection.passwordProtected, secondaryConnection.token.isEmpty {
                self.record(status: .failed, message: "The Secondary Pi-hole is signed out. Re-authenticate it in Preferences.")
                SyncProgress.report("Sync: failed — the Secondary Pi-hole is signed out. Re-authenticate it in Preferences.")
                return
            }

            let primary = Pihole6API(connection: primaryConnection)
            let secondary = Pihole6API(connection: secondaryConnection)

            do {
                // Phase 5: Sync groups first to build ID-translation maps.
                // Groups are always fetched even when skipped so adlists/domains can translate IDs.
                let (groupsSummary, primaryIdToName, secondaryNameToId) = try await self.syncGroups(
                    primary: primary, secondary: secondary,
                    dryRun: isDryRun, skip: skipGroups
                )

                // Phase 3: Adlists
                var adlistsSummary = "Adlists: skipped"
                if !skipAdlists {
                    if Preferences.standard.syncWipeSecondaryBeforeSync && !isDryRun {
                        try await self.wipeSecondaryAdlists(secondary: secondary)
                    }
                    adlistsSummary = try await self.syncAdlists(
                        primary: primary, secondary: secondary,
                        primaryIdToName: primaryIdToName,
                        secondaryNameToId: secondaryNameToId,
                        dryRun: isDryRun
                    )
                }

                // Phase 4: Domains
                var domainsSummary = "Domains: skipped"
                if !skipDomains {
                    var bucketResults: [BucketResult] = []
                    for bucket in DomainBucket.allCases {
                        let (created, updated, deleted) = try await self.syncDomainBucket(
                            bucket: bucket,
                            primary: primary, secondary: secondary,
                            primaryIdToName: primaryIdToName,
                            secondaryNameToId: secondaryNameToId,
                            dryRun: isDryRun
                        )
                        bucketResults.append((bucket, created, updated, deleted))
                    }
                    let domainParts = bucketResults.compactMap { r -> String? in
                        let phrase = isDryRun
                            ? self.changePhrase([(r.created, "to add"), (r.updated, "to update"), (r.deleted, "to remove")])
                            : self.changePhrase([(r.created, "added"), (r.updated, "updated"), (r.deleted, "removed")])
                        guard let phrase else { return nil }
                        return "\(r.bucket.friendlyLabel): \(phrase)"
                    }
                    domainsSummary = domainParts.isEmpty
                        ? "Domains: already in sync"
                        : "Domains – \(domainParts.joined(separator: "; "))"
                }

                let fullSummary = "\(groupsSummary) | \(adlistsSummary) | \(domainsSummary)"
                self.record(status: isDryRun ? .dryRun : .success, message: fullSummary)
                SyncProgress.report("Sync\(modeTag): complete. \(fullSummary)")

            } catch let apiError as APIError {
                let message: String
                switch apiError {
                case .forbidden:
                    message = "Sync failed: the Secondary Pi-hole rejected changes (403). Enable app_sudo on it (webserver.api.app_sudo=true)."
                case .unauthorized:
                    message = "Sync failed: a Pi-hole session expired (401). Re-authenticate Primary/Secondary in Preferences."
                case let .invalidResponse(statusCode: code, content: content):
                    message = self.friendlyFailureMessage(statusCode: code, content: content)
                default:
                    message = "Sync failed: \(apiError)"
                }
                self.record(status: .failed, message: message)
                SyncProgress.report(message)
            } catch {
                let message = "Sync failed: \(error.localizedDescription)"
                self.record(status: .failed, message: message)
                SyncProgress.report(message)
            }
        }
    }

    // MARK: - Status Helpers

    private func record(status: SyncStatus, message: String) {
        Preferences.standard.set(syncLastStatus: status)
        Preferences.standard.set(syncLastMessage: message)
        Preferences.standard.set(syncLastRunAt: Date())
    }

    // MARK: - Message Formatting

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private func formatted(_ count: Int) -> String {
        Self.countFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func countPhrase(_ count: Int, _ noun: String) -> String {
        "\(formatted(count)) \(count == 1 ? noun : noun + "s")"
    }

    /// Builds "2 added, 1 updated" from labeled counts, dropping zero entries.
    /// Returns nil when every count is zero so callers can say "already in sync".
    private func changePhrase(_ items: [(count: Int, label: String)]) -> String? {
        let parts = items.filter { $0.count > 0 }.map { "\(formatted($0.count)) \($0.label)" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Turns a raw Pi-hole error payload like
    /// {"error":{"key":"database_error","message":"…","hint":"database is locked"}}
    /// into a readable sentence, with a specific explanation for lock contention.
    private func friendlyFailureMessage(statusCode: Int, content: String) -> String {
        var detail = content.trimmingCharacters(in: .whitespacesAndNewlines)
        var hint: String?
        if let data = content.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any] {
            if let msg = error["message"] as? String, !msg.isEmpty { detail = msg }
            if let h = error["hint"] as? String, !h.isEmpty { hint = h }
        }

        let combined = "\(detail) \(hint ?? "")"
        if combined.localizedCaseInsensitiveContains("database is locked") {
            return "Sync paused: the Secondary Pi-hole's database is busy (it is likely updating its blocklists). Nothing was lost — sync will retry on the next run, or you can run it again in a few minutes."
        }

        var message = "Sync failed: \(detail)"
        if let hint { message += " (\(hint))" }
        message += " [HTTP \(statusCode)]"
        return message
    }

    // MARK: - Models

    private typealias BucketResult = (bucket: DomainBucket, created: Int, updated: Int, deleted: Int)

    private struct Group {
        let id: Int
        let name: String
        let enabled: Bool
        let comment: String?
    }

    private struct GroupCreateRequest: Encodable {
        let name: String
        let enabled: Bool?
        let comment: String?
    }

    private struct GroupUpdateRequest: Encodable {
        let enabled: Bool?
        let comment: String?
    }

    private struct Adlist {
        let id: Int?
        let addressStored: String
        let addressNormalized: String
        let enabled: Bool?
        let comment: String?
        let groups: [Int]
    }

    private struct AdlistCreateRequest: Encodable {
        let address: String
        let type: String
        let enabled: Bool?
        let comment: String?
        let groups: [Int]?
    }

    private struct AdlistUpdateRequest: Encodable {
        let type: String?
        let address: String?
        let enabled: Bool?
        let comment: String?
        let groups: [Int]?
    }

    private struct Domain {
        let id: Int?
        let domain: String
        let enabled: Bool?
        let comment: String?
        let groups: [Int]
    }

    private struct DomainCreateRequest: Encodable {
        let domain: String
        let enabled: Bool?
        let comment: String?
        let groups: [Int]?
    }

    private struct DomainUpdateRequest: Encodable {
        let enabled: Bool?
        let comment: String?
        let groups: [Int]?
    }

    private enum DomainBucket: CaseIterable {
        case allowExact
        case denyExact
        case allowRegex
        case denyRegex

        var bucketType: String {
            switch self {
            case .allowExact, .allowRegex: return "allow"
            case .denyExact, .denyRegex: return "deny"
            }
        }

        var kind: String {
            switch self {
            case .allowExact, .denyExact: return "exact"
            case .allowRegex, .denyRegex: return "regex"
            }
        }

        var path: String { "/domains/\(bucketType)/\(kind)" }
        var label: String { "\(bucketType)/\(kind)" }

        var friendlyLabel: String {
            switch self {
            case .allowExact: return "allowed domains"
            case .denyExact: return "denied domains"
            case .allowRegex: return "allowed regex filters"
            case .denyRegex: return "denied regex filters"
            }
        }
    }

    // MARK: - Group Sync (Phase 5)

    /// Syncs group definitions and returns ID-translation maps.
    /// Groups are always fetched even when `skip` is true so that adlists/domains can translate IDs.
    private func syncGroups(
        primary: Pihole6API,
        secondary: Pihole6API,
        dryRun: Bool,
        skip: Bool
    ) async throws -> (summary: String, primaryIdToName: [Int: String], secondaryNameToId: [String: Int]) {

        let primaryGroups = try await fetchGroups(api: primary)
        let secondaryGroups = try await fetchGroups(api: secondary)

        let pgByName = Dictionary(primaryGroups.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let sgByName = Dictionary(secondaryGroups.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        // Compute planned changes
        var toCreate: [(String, Group)] = []
        var toUpdate: [(String, Group)] = []
        var toDisable: [String] = []

        for (name, primaryGroup) in pgByName {
            if let secGroup = sgByName[name] {
                if secGroup.enabled != primaryGroup.enabled || secGroup.comment != primaryGroup.comment {
                    toUpdate.append((name, primaryGroup))
                }
            } else {
                toCreate.append((name, primaryGroup))
            }
        }
        for (name, secGroup) in sgByName where pgByName[name] == nil {
            if secGroup.enabled { toDisable.append(name) }
        }

        // Apply unless skipped or dry-run
        if !skip && !dryRun {
            for (name, group) in toCreate {
                try await createGroup(api: secondary, name: name, enabled: group.enabled, comment: group.comment)
            }
            for (name, group) in toUpdate {
                try await updateGroup(api: secondary, name: name, enabled: group.enabled, comment: group.comment)
            }
            for name in toDisable {
                if let secGroup = sgByName[name] {
                    try await updateGroup(api: secondary, name: name, enabled: false, comment: secGroup.comment)
                }
            }
        }

        let primaryIdToName = Dictionary(primaryGroups.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

        // Re-fetch secondary only if we actually created new groups (so we get their IDs).
        let sgFinal: [Group]
        if !skip && !dryRun && !toCreate.isEmpty {
            sgFinal = try await fetchGroups(api: secondary)
        } else {
            sgFinal = secondaryGroups
        }
        let secondaryNameToId = Dictionary(sgFinal.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })

        let summary: String
        if skip {
            summary = "Groups: skipped"
        } else if dryRun {
            let phrase = changePhrase([(toCreate.count, "to add"), (toUpdate.count, "to update"), (toDisable.count, "to disable")])
            summary = "[Dry run] Groups: \(phrase ?? "already in sync")"
        } else {
            let phrase = changePhrase([(toCreate.count, "added"), (toUpdate.count, "updated"), (toDisable.count, "disabled")])
            summary = "Groups: \(phrase ?? "already in sync")"
        }

        SyncProgress.report("Sync: \(summary)")
        return (summary, primaryIdToName, secondaryNameToId)
    }

    private func fetchGroups(api: Pihole6API) async throws -> [Group] {
        let data = try await api.getData("/groups")
        let object = try JSONSerialization.jsonObject(with: data)

        let array: [Any]
        if let dict = object as? [String: Any], let raw = dict["groups"] as? [Any] {
            array = raw
        } else if let raw = object as? [Any] {
            array = raw
        } else {
            return []
        }

        return array.compactMap { item in
            guard let d = item as? [String: Any] else { return nil }
            guard let name = d["name"] as? String, !name.isEmpty else { return nil }
            guard let id = d["id"] as? Int else { return nil }
            let enabled = (d["enabled"] as? Bool) ?? true
            let comment = d["comment"] as? String
            return Group(id: id, name: name, enabled: enabled, comment: comment)
        }
    }

    private func createGroup(api: Pihole6API, name: String, enabled: Bool, comment: String?) async throws {
        _ = try await api.postData(
            "/groups",
            queryItems: [URLQueryItem(name: "app_sudo", value: "true")],
            body: GroupCreateRequest(name: name, enabled: enabled, comment: comment)
        )
    }

    private func updateGroup(api: Pihole6API, name: String, enabled: Bool, comment: String?) async throws {
        let encoded = Pihole6API.encodePathComponent(name)
        _ = try await api.putData(
            "/groups/\(encoded)",
            queryItems: [URLQueryItem(name: "app_sudo", value: "true")],
            body: GroupUpdateRequest(enabled: enabled, comment: comment)
        )
    }

    // MARK: - Group ID Translation

    private func translateGroupIds(
        _ primaryIds: [Int],
        primaryIdToName: [Int: String],
        secondaryNameToId: [String: Int]
    ) -> [Int] {
        primaryIds.compactMap { id in
            guard let name = primaryIdToName[id] else { return nil }
            return secondaryNameToId[name]
        }
    }

    // MARK: - Adlist Sync (Phase 3)

    private func syncAdlists(
        primary: Pihole6API,
        secondary: Pihole6API,
        primaryIdToName: [Int: String],
        secondaryNameToId: [String: Int],
        dryRun: Bool
    ) async throws -> String {
        SyncProgress.report("Sync: fetching adlists…")
        let pl = try await fetchAdlists(api: primary)
        let slRaw = try await fetchAdlists(api: secondary)

        // Only sanitise percent-encoded URLs when we can actually write fixes.
        let sl = dryRun ? slRaw : (try await sanitizeSecondaryPercentEncodedLists(secondary: secondary, lists: slRaw))

        let primaryByAddress = indexAdlistsByNormalizedAddress(pl)
        let secondaryByAddress = indexAdlistsByNormalizedAddress(sl)

        let primaryKeys = Set(primaryByAddress.keys)
        let secondaryKeys = Set(secondaryByAddress.keys)

        let toDelete = Array(secondaryKeys.subtracting(primaryKeys)).sorted()
        let toUpsert = Array(primaryKeys).sorted()

        if toDelete.isEmpty {
            SyncProgress.report("Sync: \(dryRun ? "[dry run] " : "")Primary has \(countPhrase(toUpsert.count, "adlist")); Secondary has no extras.")
        } else if dryRun {
            SyncProgress.report("Sync: [dry run] Primary has \(countPhrase(toUpsert.count, "adlist")); \(countPhrase(toDelete.count, "extra adlist")) would be removed from Secondary.")
        } else {
            SyncProgress.report("Sync: Primary has \(countPhrase(toUpsert.count, "adlist")); removing \(countPhrase(toDelete.count, "extra adlist")) from Secondary…")
        }

        var deleted = 0
        var disabled = 0
        for address in toDelete {
            guard let list = secondaryByAddress[address] else { continue }
            let removedSoFar = deleted + disabled
            if !dryRun, removedSoFar > 0, removedSoFar % 50 == 0 {
                SyncProgress.report("Sync: removing extra adlists (\(formatted(removedSoFar)) of \(formatted(toDelete.count)))…")
            }
            if !dryRun {
                if let id = list.id {
                    do {
                        _ = try await secondary.deleteData(
                            "/lists/\(id)",
                            queryItems: [
                                URLQueryItem(name: "type", value: "block"),
                                URLQueryItem(name: "app_sudo", value: "true"),
                            ]
                        )
                        deleted += 1
                        continue
                    } catch let apiError as APIError {
                        if case .invalidResponse(statusCode: 404, content: _) = apiError {
                            // fall through to disable
                        } else {
                            throw apiError
                        }
                    }
                }
                try await disableAdlist(secondary: secondary, list: list)
                disabled += 1
            } else {
                deleted += 1
            }
        }

        var created = 0
        var updated = 0
        for address in toUpsert {
            guard let desired = primaryByAddress[address] else { continue }
            let existing = secondaryByAddress[address]
            let translatedGroups = translateGroupIds(desired.groups, primaryIdToName: primaryIdToName, secondaryNameToId: secondaryNameToId)

            if !dryRun {
                let writeAddress = syncAdlistSanitizeWriteAddress(desired.addressNormalized)
                if let existingId = existing?.id {
                    _ = try await secondary.putData(
                        "/lists/\(existingId)",
                        queryItems: [
                            URLQueryItem(name: "type", value: "block"),
                            URLQueryItem(name: "app_sudo", value: "true"),
                        ],
                        body: AdlistUpdateRequest(
                            type: "block", address: writeAddress,
                            enabled: desired.enabled, comment: desired.comment, groups: translatedGroups
                        )
                    )
                } else {
                    _ = try await secondary.postData(
                        "/lists",
                        queryItems: [
                            URLQueryItem(name: "type", value: "block"),
                            URLQueryItem(name: "app_sudo", value: "true"),
                        ],
                        body: AdlistCreateRequest(
                            address: writeAddress, type: "block",
                            enabled: desired.enabled, comment: desired.comment, groups: translatedGroups
                        )
                    )
                }
            }

            if existing != nil { updated += 1 } else { created += 1 }

            let processed = created + updated
            if processed % 25 == 0 {
                SyncProgress.report("Sync: updating adlists (\(formatted(processed)) of \(formatted(toUpsert.count)))…")
            }
        }

        if dryRun {
            let phrase = changePhrase([(created, "to add"), (updated, "to update"), (deleted, "to remove")])
            return "[Dry run] Adlists: \(phrase ?? "already in sync")"
        }
        let phrase = changePhrase([(created, "added"), (updated, "updated"), (deleted, "removed"), (disabled, "disabled")])
        return "Adlists: \(phrase ?? "already in sync")"
    }

    private func fetchAdlists(api: Pihole6API) async throws -> [Adlist] {
        let data = try await api.getData(
            "/lists",
            queryItems: [URLQueryItem(name: "type", value: "block")]
        )
        let object = try JSONSerialization.jsonObject(with: data)

        let array: [Any]
        if let dict = object as? [String: Any], let raw = dict["lists"] as? [Any] {
            array = raw
        } else if let raw = object as? [Any] {
            array = raw
        } else {
            return []
        }

        return array.compactMap { item in
            guard let d = item as? [String: Any] else { return nil }
            if let type = d["type"] as? String, type != "block" { return nil }
            let id = d["id"] as? Int
            guard let addressStored = d["address"] as? String, !addressStored.isEmpty else { return nil }
            let addressNormalized = addressStored.removingPercentEncoding ?? addressStored
            let enabled = d["enabled"] as? Bool
            let comment = d["comment"] as? String
            let groups = d["groups"] as? [Int] ?? []
            return Adlist(
                id: id, addressStored: addressStored, addressNormalized: addressNormalized,
                enabled: enabled, comment: comment, groups: groups
            )
        }
    }

    private func indexAdlistsByNormalizedAddress(_ lists: [Adlist]) -> [String: Adlist] {
        var result: [String: Adlist] = [:]
        for list in lists {
            let key = list.addressNormalized
            if let existing = result[key] {
                result[key] = preferredAdlist(existing: existing, candidate: list)
            } else {
                result[key] = list
            }
        }
        return result
    }

    private func preferredAdlist(existing: Adlist, candidate: Adlist) -> Adlist {
        let existingEncoded = syncAdlistLooksPercentEncoded(existing.addressStored)
        let candidateEncoded = syncAdlistLooksPercentEncoded(candidate.addressStored)
        if existingEncoded != candidateEncoded {
            return existingEncoded ? candidate : existing
        }
        return (existing.enabled ?? true) ? existing : candidate
    }

    private func sanitizeSecondaryPercentEncodedLists(secondary: Pihole6API, lists: [Adlist]) async throws -> [Adlist] {
        let bad = lists.filter {
            guard syncAdlistLooksPercentEncoded($0.addressStored) else { return false }
            return ($0.addressStored.removingPercentEncoding ?? $0.addressStored) != $0.addressStored
        }
        guard !bad.isEmpty else { return lists }

        SyncProgress.report("Sync: repairing \(countPhrase(bad.count, "malformed adlist URL")) on Secondary…")
        var fixedIdToDecoded: [Int: String] = [:]

        for list in bad {
            guard let id = list.id else { continue }
            let decoded = list.addressStored.removingPercentEncoding ?? list.addressStored
            let fixed = syncAdlistSanitizeWriteAddress(decoded)

            do {
                _ = try await secondary.putData(
                    "/lists/\(id)",
                    queryItems: [
                        URLQueryItem(name: "type", value: "block"),
                        URLQueryItem(name: "app_sudo", value: "true"),
                    ],
                    body: AdlistUpdateRequest(
                        type: "block", address: fixed, enabled: false,
                        comment: "Fixed by PiGuard sync (was percent-encoded)", groups: nil
                    )
                )
                fixedIdToDecoded[id] = fixed
                continue
            } catch {
                Log.warn("Sync: could not fix percent-encoded adlist \(id): \(error)")
            }

            do {
                _ = try await secondary.deleteData(
                    "/lists/\(id)",
                    queryItems: [
                        URLQueryItem(name: "type", value: "block"),
                        URLQueryItem(name: "app_sudo", value: "true"),
                    ]
                )
            } catch let deleteError as APIError {
                if case .invalidResponse(statusCode: 404, content: _) = deleteError { /* already gone */ } else {
                    _ = try? await secondary.putData(
                        "/lists/\(id)",
                        queryItems: [
                            URLQueryItem(name: "type", value: "block"),
                            URLQueryItem(name: "app_sudo", value: "true"),
                        ],
                        body: AdlistUpdateRequest(
                            type: "block", address: nil, enabled: false,
                            comment: "Disabled by PiGuard sync (invalid encoded URL)", groups: nil
                        )
                    )
                }
            }
        }

        return lists.compactMap { list in
            if let id = list.id, let decoded = fixedIdToDecoded[id] {
                return Adlist(id: id, addressStored: decoded, addressNormalized: decoded, enabled: false, comment: list.comment, groups: list.groups)
            }
            let decoded = list.addressStored.removingPercentEncoding ?? list.addressStored
            if decoded != list.addressStored, syncAdlistLooksPercentEncoded(list.addressStored) { return nil }
            return list
        }
    }

    private func wipeSecondaryAdlists(secondary: Pihole6API) async throws {
        SyncProgress.report("Sync: removing all adlists from Secondary before syncing (wipe option is on)…")
        let lists = try await fetchAdlists(api: secondary)
        guard !lists.isEmpty else {
            SyncProgress.report("Sync: Secondary has no adlists to remove.")
            return
        }
        var wiped = 0
        for list in lists {
            guard let id = list.id else { continue }
            do {
                _ = try await secondary.deleteData(
                    "/lists/\(id)",
                    queryItems: [
                        URLQueryItem(name: "type", value: "block"),
                        URLQueryItem(name: "app_sudo", value: "true"),
                    ]
                )
                wiped += 1
            } catch let apiError as APIError {
                switch apiError {
                case .invalidResponse(statusCode: 404, content: _): break
                default:
                    _ = try? await secondary.putData(
                        "/lists/\(id)",
                        queryItems: [
                            URLQueryItem(name: "type", value: "block"),
                            URLQueryItem(name: "app_sudo", value: "true"),
                        ],
                        body: AdlistUpdateRequest(type: "block", address: nil, enabled: false, comment: "Disabled by PiGuard pre-clean", groups: nil)
                    )
                }
            }
            if wiped % 50 == 0 {
                SyncProgress.report("Sync: wiping adlists (\(formatted(wiped)) of \(formatted(lists.count)))…")
            }
        }
        SyncProgress.report("Sync: wipe complete — \(countPhrase(wiped, "adlist")) removed.")
    }

    private func disableAdlist(secondary: Pihole6API, list: Adlist) async throws {
        guard let id = list.id else { return }
        _ = try await secondary.putData(
            "/lists/\(id)",
            queryItems: [
                URLQueryItem(name: "type", value: "block"),
                URLQueryItem(name: "app_sudo", value: "true"),
            ],
            body: AdlistUpdateRequest(type: "block", address: nil, enabled: false, comment: "Disabled by PiGuard sync", groups: nil)
        )
    }

    // MARK: - Domain Sync (Phase 4)

    private func syncDomainBucket(
        bucket: DomainBucket,
        primary: Pihole6API,
        secondary: Pihole6API,
        primaryIdToName: [Int: String],
        secondaryNameToId: [String: Int],
        dryRun: Bool
    ) async throws -> (created: Int, updated: Int, deleted: Int) {

        SyncProgress.report("Sync: \(dryRun ? "[dry run] " : "")checking \(bucket.friendlyLabel)…")

        let primaryDomains = try await fetchDomains(api: primary, bucket: bucket)
        let secondaryDomains = try await fetchDomains(api: secondary, bucket: bucket)

        let primaryByDomain = Dictionary(primaryDomains.map { ($0.domain, $0) }, uniquingKeysWith: { a, _ in a })
        let secondaryByDomain = Dictionary(secondaryDomains.map { ($0.domain, $0) }, uniquingKeysWith: { a, _ in a })

        let toDelete = Array(Set(secondaryByDomain.keys).subtracting(primaryByDomain.keys))
        let toUpsert = Array(primaryByDomain.keys)

        var deleted = 0
        for domainStr in toDelete {
            guard let existing = secondaryByDomain[domainStr] else { continue }
            if !dryRun {
                try await deleteDomain(api: secondary, domain: existing, bucket: bucket)
            }
            deleted += 1
        }

        var created = 0
        var updated = 0
        for domainStr in toUpsert {
            guard let desired = primaryByDomain[domainStr] else { continue }
            let existing = secondaryByDomain[domainStr]
            let translatedGroups = translateGroupIds(
                desired.groups, primaryIdToName: primaryIdToName, secondaryNameToId: secondaryNameToId
            )

            if !dryRun {
                if existing != nil {
                    let encoded = Pihole6API.encodePathComponent(domainStr)
                    _ = try await secondary.putData(
                        "\(bucket.path)/\(encoded)",
                        queryItems: [URLQueryItem(name: "app_sudo", value: "true")],
                        body: DomainUpdateRequest(enabled: desired.enabled, comment: desired.comment, groups: translatedGroups)
                    )
                } else {
                    _ = try await secondary.postData(
                        bucket.path,
                        queryItems: [URLQueryItem(name: "app_sudo", value: "true")],
                        body: DomainCreateRequest(
                            domain: domainStr, enabled: desired.enabled,
                            comment: desired.comment, groups: translatedGroups
                        )
                    )
                }
            }

            if existing != nil { updated += 1 } else { created += 1 }
        }

        return (created, updated, deleted)
    }

    private func fetchDomains(api: Pihole6API, bucket: DomainBucket) async throws -> [Domain] {
        let data = try await api.getData(bucket.path)
        let object = try JSONSerialization.jsonObject(with: data)

        let array: [Any]
        if let dict = object as? [String: Any], let raw = dict["domains"] as? [Any] {
            array = raw
        } else if let raw = object as? [Any] {
            array = raw
        } else {
            return []
        }

        return array.compactMap { item in
            guard let d = item as? [String: Any] else { return nil }
            guard let domain = d["domain"] as? String, !domain.isEmpty else { return nil }
            let id = d["id"] as? Int
            let enabled = d["enabled"] as? Bool
            let comment = d["comment"] as? String
            let groups = d["groups"] as? [Int] ?? []
            return Domain(id: id, domain: domain, enabled: enabled, comment: comment, groups: groups)
        }
    }

    private func deleteDomain(api: Pihole6API, domain: Domain, bucket: DomainBucket) async throws {
        if let id = domain.id {
            do {
                _ = try await api.deleteData(
                    "/domains/\(id)",
                    queryItems: [URLQueryItem(name: "app_sudo", value: "true")]
                )
                return
            } catch let apiError as APIError {
                if case .invalidResponse(statusCode: 404, content: _) = apiError { return }
                // For other errors, fall through to path-based delete.
            }
        }

        let encoded = Pihole6API.encodePathComponent(domain.domain)
        _ = try await api.deleteData(
            "\(bucket.path)/\(encoded)",
            queryItems: [URLQueryItem(name: "app_sudo", value: "true")]
        )
    }

}
