//
//  WidgetSnapshotStore.swift
//  PiGuard
//
//  Shared between the PiGuard main app target and the PiGuardWidget extension target.
//  Must not import AppKit or Cocoa.
//
//  Primary channel: Keychain (team-scoped access group GB7Z2TZ8LT.com.foosmith.PiGuard).
//    Both targets have keychain-access-groups: ["GB7Z2TZ8LT.*"] in their provisioning
//    profiles, so no additional App Group portal registration is needed.
//  Secondary channel: App Group shared file container (works when fully provisioned).
//  Tertiary channel: NSDistributedNotificationCenter local cache.

import Foundation
import Security

enum WidgetSnapshotStore {
    static let appGroupID = "group.com.foosmith.PiGuard"
    static let distributedNotificationName = "com.foosmith.PiGuard.widgetSnapshot"
    static let snapshotRequestNotificationName = "com.foosmith.PiGuard.widgetSnapshotRequest"
    private static let localCacheKey = "com.foosmith.PiGuard.cachedSnapshot"

    // MARK: - Keychain (primary — works with team wildcard, no App Group portal setup needed)

    private static let keychainService = "com.foosmith.PiGuard.widgetSnapshot"
    private static let keychainAccount = "snapshot"
    private static let keychainAccessGroup = "GB7Z2TZ8LT.com.foosmith.PiGuard"

    static func writeKeychain(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        let query: [CFString: Any] = [
            kSecClass:                      kSecClassGenericPassword,
            kSecAttrService:                keychainService,
            kSecAttrAccount:                keychainAccount,
            kSecAttrAccessGroup:            keychainAccessGroup,
            kSecUseDataProtectionKeychain:  true,
        ]
        let update: [CFString: Any] = [kSecValueData: data]

        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData]              = data
            add[kSecAttrAccessible]         = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func readKeychain() -> WidgetSnapshot? {
        let query: [CFString: Any] = [
            kSecClass:                      kSecClassGenericPassword,
            kSecAttrService:                keychainService,
            kSecAttrAccount:                keychainAccount,
            kSecAttrAccessGroup:            keychainAccessGroup,
            kSecUseDataProtectionKeychain:  true,
            kSecReturnData:                 true,
            kSecMatchLimit:                 kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    // MARK: - App Group file (secondary)

    private static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("widget_snapshot.json")
    }

    static func write(_ snapshot: WidgetSnapshot) {
        writeKeychain(snapshot)
        guard let url = snapshotURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    // MARK: - Local UserDefaults cache (tertiary — widget's own container)

    static func writeLocalCache(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: localCacheKey)
    }

    static func readLocalCache() -> WidgetSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: localCacheKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    // MARK: - Best available

    /// Tries Keychain first, then App Group file, then local notification cache.
    static func readBest() -> WidgetSnapshot? {
        readKeychain() ?? read() ?? readLocalCache()
    }
}
