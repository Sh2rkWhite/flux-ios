import Foundation
import Security

/// Minimal iOS Keychain wrapper — the equivalent of the Android app's
/// encrypted `flutter_secure_storage` vault.
struct KeychainStore {
    let service: String = "com.flux3.ios.vault"

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ key: String, _ value: String) throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// A single stored account snapshot — enough to switch back without
/// re-authenticating. Persisted in the Keychain as a JSON list.
struct StoredAccount: Identifiable, Codable, Equatable {
    var fluxId: String
    var username: String
    var displayName: String
    var avatarPath: String?
    /// Opaque UUID minted at login — used for session-dedup guards.
    var sessionToken: String
    var lastLoginAtMs: Int
    /// Plaintext password — only stored when "Remember Me" was opted in,
    /// exclusively inside the encrypted vault.
    var password: String?
    var rememberMe: Bool

    var id: String { fluxId }
}

/// Multi-account manager. Credentials live in the Keychain so they survive
/// app restarts but never touch plain UserDefaults.
@MainActor
final class AccountManager: ObservableObject {
    static let kAccounts = "flux.accounts.v1"
    static let kActive = "flux.active.v1"

    private let vault = KeychainStore()
    @Published private(set) var accounts: [StoredAccount] = []
    @Published private(set) var activeFluxId: String?
    @Published private(set) var ready = false

    /// Reads the vault and restores the account list + active selection.
    func initManager() {
        if let raw = vault.read(Self.kAccounts), !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let list = try? JSONDecoder().decode([StoredAccount].self, from: data) {
            accounts = list
        }
        activeFluxId = vault.read(Self.kActive)
        ready = true
    }

    /// Adds the account (replacing any prior entry with the same fluxId)
    /// and makes it active.
    func addAccount(_ account: StoredAccount) {
        accounts = [account] + accounts.filter { $0.fluxId != account.fluxId }
        activeFluxId = account.fluxId
        persist()
    }

    /// Switches the active account without logging out.
    func switchTo(_ fluxId: String) {
        guard activeFluxId != fluxId, accounts.contains(where: { $0.fluxId == fluxId }) else { return }
        activeFluxId = fluxId
        persist()
    }

    /// Removes an account entry; the next account (if any) becomes active.
    func removeAccount(_ fluxId: String) {
        accounts = accounts.filter { $0.fluxId != fluxId }
        if activeFluxId == fluxId {
            activeFluxId = accounts.first?.fluxId
        }
        persist()
    }

    var active: StoredAccount? {
        guard let activeFluxId else { return nil }
        return accounts.first { $0.fluxId == activeFluxId }
    }

    /// The most recently stored account with "Remember Me" enabled — used
    /// by the auth screen to pre-fill credentials.
    var lastRemembered: StoredAccount? {
        accounts.first { $0.rememberMe && $0.password != nil }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(accounts), let json = String(data: data, encoding: .utf8) {
            try? vault.write(Self.kAccounts, json)
        }
        try? vault.write(Self.kActive, activeFluxId ?? "")
    }
}
