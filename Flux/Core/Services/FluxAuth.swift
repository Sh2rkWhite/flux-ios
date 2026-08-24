import Foundation
import FirebaseAuth

/// Result of a Firebase Auth sign-in attempt.
struct FluxAuthOutcome {
    var uid: String?
    var error: String?
    var notFound = false
    var unavailable = false

    var ok: Bool { uid != nil }
}

/// Firebase Authentication bridge for Flux (iOS).
///
/// Every Flux account maps to a stable synthetic email derived from its
/// FluxID (`flx-xxxxxxxx@users.flux3.app`) — identical to the Android
/// client, so the same account signs in on both platforms. Passwords are
/// verified by Firebase Auth only; they are never stored in Firestore and
/// no password hash ever leaves the device.
enum FluxAuth {

    static func emailForFluxId(_ fluxId: String) -> String {
        "\(fluxId.lowercased())@users.flux3.app"
    }

    static var currentUid: String? {
        Auth.auth().currentUser?.uid
    }

    /// Creates the Firebase Auth account for a freshly registered Flux user.
    static func register(fluxId: String, password: String) async -> FluxAuthOutcome {
        do {
            let result = try await Auth.auth().createUser(
                withEmail: emailForFluxId(fluxId),
                password: password
            )
            return FluxAuthOutcome(uid: result.user.uid)
        } catch let error as NSError {
            print("FluxAuth register error: \(error.code)")
            if AuthErrorCode(rawValue: error.code) == .emailAlreadyInUse {
                // Already migrated (race between devices) — sign in instead.
                return await signIn(fluxId: fluxId, password: password)
            }
            return FluxAuthOutcome(error: mapError(error))
        }
    }

    /// Signs in an existing Flux account via Firebase Auth.
    static func signIn(fluxId: String, password: String) async -> FluxAuthOutcome {
        do {
            let result = try await Auth.auth().signIn(
                withEmail: emailForFluxId(fluxId),
                password: password
            )
            return FluxAuthOutcome(uid: result.user.uid)
        } catch let error as NSError {
            print("FluxAuth signIn error: \(error.code)")
            if AuthErrorCode(rawValue: error.code) == .userNotFound {
                var outcome = FluxAuthOutcome()
                outcome.notFound = true
                return outcome
            }
            return FluxAuthOutcome(error: mapError(error))
        }
    }

    /// Signs out of Firebase Auth. Never throws.
    static func signOut() {
        try? Auth.auth().signOut()
    }

    private static func mapError(_ error: NSError) -> String {
        guard let code = AuthErrorCode(rawValue: error.code) else {
            return "Ошибка авторизации"
        }
        switch code {
        case .invalidCredential, .wrongPassword, .invalidEmail:
            return "Неверный пароль"
        case .userDisabled:
            return "Аккаунт заблокирован"
        case .weakPassword:
            return "Пароль слишком короткий (минимум 6 символов)"
        case .tooManyRequests:
            return "Слишком много попыток. Попробуйте позже."
        case .networkError:
            return "Нет соединения с сервером"
        case .operationNotAllowed:
            return "Вход временно недоступен. Обратитесь в поддержку."
        default:
            return "Ошибка авторизации (\(error.code))"
        }
    }
}
