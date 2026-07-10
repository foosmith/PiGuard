//
//  KeychainCredentialStore.swift
//  PiGuard
//
//  Created by Codex on 3/12/26.
//

import Foundation
import Security

enum KeychainCredentialStoreError: Error {
    case unexpectedData
    case unhandledStatus(OSStatus)
}

final class KeychainCredentialStore {
    static let shared = KeychainCredentialStore()

    private let service: String
    private let accessGroup: String
    private let lock = NSLock()

    private enum CachedValue {
        case value(String)
        case missing
    }

    private var cache: [String: CachedValue] = [:]

    // Credentials live in the data protection keychain under the app-group
    // access group, which both the sandboxed App Store build and the
    // non-sandboxed Developer ID build can read (authorized by the
    // com.apple.security.application-groups entitlement). Legacy items in the
    // per-signature file keychain are migrated on first read. Builds without
    // group authorization (e.g. ad-hoc debug) get errSecMissingEntitlement,
    // so they fall back to the file keychain entirely.
    private var sharedKeychainUsable: Bool

    init(service: String = Bundle.main.bundleIdentifier ?? "com.foosmith.PiGuard",
         accessGroup: String = WidgetSnapshotStore.appGroupID) {
        self.service = service
        self.accessGroup = accessGroup
        if #available(macOS 10.15, *) {
            sharedKeychainUsable = true
        } else {
            sharedKeychainUsable = false
        }
    }

    func readString(account: String) throws -> String? {
        if let cached = cachedValue(for: account) {
            switch cached {
            case let .value(value): return value
            case .missing: return nil
            }
        }

        if isSharedKeychainUsable {
            do {
                if let value = try copyString(account: account, shared: true) {
                    setCachedValue(.value(value), for: account)
                    return value
                }
                // Not in the shared keychain yet — migrate any legacy item
                // this build is still able to read.
                if let legacy = try? copyString(account: account, shared: false) {
                    try? upsert(legacy, account: account, shared: true)
                    try? deleteItem(account: account, shared: false)
                    setCachedValue(.value(legacy), for: account)
                    return legacy
                }
                setCachedValue(.missing, for: account)
                return nil
            } catch KeychainCredentialStoreError.unhandledStatus(let status) where status == errSecMissingEntitlement {
                markSharedKeychainUnusable()
            }
        }

        let value = try copyString(account: account, shared: false)
        if let value {
            setCachedValue(.value(value), for: account)
        } else {
            setCachedValue(.missing, for: account)
        }
        return value
    }

    func upsertString(_ value: String, account: String) throws {
        if isSharedKeychainUsable {
            do {
                try upsert(value, account: account, shared: true)
                setCachedValue(.value(value), for: account)
                return
            } catch KeychainCredentialStoreError.unhandledStatus(let status) where status == errSecMissingEntitlement {
                markSharedKeychainUnusable()
            }
        }
        try upsert(value, account: account, shared: false)
        setCachedValue(.value(value), for: account)
    }

    func delete(account: String) throws {
        if isSharedKeychainUsable {
            do {
                try deleteItem(account: account, shared: true)
            } catch KeychainCredentialStoreError.unhandledStatus(let status) where status == errSecMissingEntitlement {
                markSharedKeychainUnusable()
            }
        }
        try deleteItem(account: account, shared: false)
        setCachedValue(.missing, for: account)
    }

    // MARK: - Keychain primitives

    private func copyString(account: String, shared: Bool) throws -> String? {
        var query = baseQuery(account: account, shared: shared)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainCredentialStoreError.unhandledStatus(status)
        }
        guard let data = item as? Data else {
            throw KeychainCredentialStoreError.unexpectedData
        }
        return String(data: data, encoding: .utf8)
    }

    private func upsert(_ value: String, account: String, shared: Bool) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account, shared: shared)

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let attributes: [String: Any] = [
                kSecValueData as String: data,
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainCredentialStoreError.unhandledStatus(updateStatus)
            }
            return
        }
        if status != errSecItemNotFound {
            throw KeychainCredentialStoreError.unhandledStatus(status)
        }

        var insert = query
        insert[kSecValueData as String] = data
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainCredentialStoreError.unhandledStatus(addStatus)
        }
    }

    private func deleteItem(account: String, shared: Bool) throws {
        let status = SecItemDelete(baseQuery(account: account, shared: shared) as CFDictionary)
        if status == errSecItemNotFound || status == errSecSuccess {
            return
        }
        throw KeychainCredentialStoreError.unhandledStatus(status)
    }

    private func baseQuery(account: String, shared: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if shared, #available(macOS 10.15, *) {
            query[kSecUseDataProtectionKeychain as String] = true
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    // MARK: - State

    private var isSharedKeychainUsable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sharedKeychainUsable
    }

    private func markSharedKeychainUnusable() {
        lock.lock()
        sharedKeychainUsable = false
        lock.unlock()
    }

    private func cachedValue(for account: String) -> CachedValue? {
        lock.lock()
        defer { lock.unlock() }
        return cache[account]
    }

    private func setCachedValue(_ value: CachedValue, for account: String) {
        lock.lock()
        cache[account] = value
        lock.unlock()
    }
}
