import Foundation
import CryptoKit

/// Salted SHA-256 storage for PINs and passwords.
///
/// The plain value never touches disk: we store `salt:sha256(salt:value)`
/// — the exact scheme used by the Android implementation, so hashes are
/// interchangeable between platforms.
enum PinHash {
    static func hash(_ pin: String, salt: String? = nil) -> String {
        let s = salt ?? String(Int(Date().timeIntervalSince1970 * 1_000_000), radix: 36)
        let digest = SHA256.hash(data: Data("\(s):\(pin)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(s):\(hex)"
    }

    static func verify(_ pin: String, stored: String) -> Bool {
        guard let idx = stored.firstIndex(of: ":"), idx > stored.startIndex else { return false }
        let salt = String(stored[stored.startIndex..<idx])
        return hash(pin, salt: salt) == stored
    }
}

/// Tracks whether the messenger is currently behind the lock screen.
@MainActor
final class LockController: ObservableObject {
    @Published private(set) var locked = false

    func lock() {
        if !locked { locked = true }
    }

    func unlock() {
        if locked { locked = false }
    }
}
