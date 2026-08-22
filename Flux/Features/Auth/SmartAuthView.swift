import SwiftUI
import LocalAuthentication

/// Three-step auth state machine: username lookup → login (existing) or
/// registration (free). Successful auth stores the session in the
/// multi-account vault and the root flips to the messenger.
struct SmartAuthView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var accountManager: AccountManager
    @EnvironmentObject var l10n: FluxL10n

    private enum Step: Equatable {
        case username
        case login(FluxUser)
        case register(String)
    }

    @State private var step: Step = .username
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var displayName = ""
    @State private var rememberMe = false
    @State private var busy = false
    @State private var errorText: String?

    private static let usernameRegex = "^[a-zA-Z0-9_]{3,20}$"

    private var usernameValid: Bool {
        username.range(of: Self.usernameRegex, options: .regularExpression) != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch step {
                case .username: usernameStep
                case .login(let user): loginStep(user)
                case .register(let name): registerStep(name)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FluxColors.background.ignoresSafeArea())
        .onAppear { prefillRemembered() }
    }

    // MARK: Step 1 — username

    private var usernameStep: some View {
        VStack(spacing: 0) {
            FluxLogoMark(size: 56)
                .padding(.top, 40)

            Text(l10n.authWelcome)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(FluxColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 40)

            Text(l10n.authSubtitle)
                .font(.system(size: 16))
                .foregroundStyle(FluxColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)

            Text(l10n.authUsername)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(FluxColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 32)

            FluxTextField(
                text: $username,
                hint: "username",
                autofocus: true,
                maxLength: 20,
                onSubmitted: { checkUsername() }
            )
            .padding(.top, 8)

            HStack(spacing: 8) {
                Image(systemName: usernameValid ? "checkmark.circle.fill" : "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(usernameValid ? FluxColors.online : FluxColors.textTertiary)
                Text(l10n.authUsernameHint)
                    .font(.system(size: 13))
                    .foregroundStyle(usernameValid ? FluxColors.online : FluxColors.textTertiary)
                Spacer()
            }
            .padding(.top, 8)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FluxColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }

            FluxButton(title: l10n.authCheckUsername, enabled: usernameValid && !busy, showsProgress: busy) {
                checkUsername()
            }
            .padding(.top, 28)

            if let bio = backend.biometricLoginUsername, biometricsAvailable() {
                VStack(spacing: 0) {
                    Divider()
                        .overlay(FluxColors.separator)
                        .padding(.vertical, 20)
                    biometricCard(username: bio)
                }
                .padding(.top, 24)
            }
        }
    }

    private func biometricCard(username: String) -> some View {
        Button {
            authenticateBiometric(username: username)
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FluxColors.gradient)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "faceid")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.authBiometricLogin)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FluxColors.blue)
                    Text("@\(username)")
                        .font(.system(size: 13))
                        .foregroundStyle(FluxColors.textSecondary)
                }
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(FluxColors.blueSoft.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(FluxColors.blue.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: Step 2 — login

    private func loginStep(_ user: FluxUser) -> some View {
        VStack(spacing: 0) {
            backButton { resetToUsername() }
                .padding(.bottom, 20)

            FluxLogoMark(size: 56)

            Text(l10n.authExistingAccount)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(FluxColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 32)

            Text("@\(user.username ?? username)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(FluxColors.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            FluxSecureField(text: $password, hint: l10n.authPassword, autofocus: true, onSubmitted: { login(user) })
                .padding(.top, 28)

            Button {
                rememberMe.toggle()
                Haptics.selection()
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(rememberMe ? FluxColors.blue : FluxColors.textTertiary, lineWidth: 1.5)
                        .background(RoundedRectangle(cornerRadius: 4).fill(rememberMe ? FluxColors.blue : .clear))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(rememberMe ? 1 : 0)
                        )
                    Text(l10n.authRememberMe)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FluxColors.textSecondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FluxColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }

            FluxButton(title: l10n.authLogin, enabled: password.count >= 4 && !busy, showsProgress: busy) {
                login(user)
            }
            .padding(.top, 28)
        }
    }

    // MARK: Step 3 — register

    private func registerStep(String) -> some View {
        VStack(spacing: 0) {
            backButton { resetToUsername() }
                .padding(.bottom, 20)

            FluxLogoMark(size: 56)

            Text(l10n.authNewAccount)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(FluxColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 32)

            Text("@\(username)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(FluxColors.online)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            FluxTextField(text: $displayName, hint: l10n.authDisplayName, autofocus: true, maxLength: 32)
                .padding(.top, 24)
            FluxTextField(text: $email, hint: l10n.authEmail, keyboard: .email)
                .padding(.top, 16)
            FluxSecureField(text: $password, hint: l10n.authPassword, onSubmitted: { register() })
                .padding(.top, 16)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FluxColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }

            FluxButton(title: l10n.authRegister, enabled: registerValid && !busy, showsProgress: busy) {
                register()
            }
            .padding(.top, 28)
        }
    }

    private var registerValid: Bool {
        email.contains("@") && email.contains(".")
            && password.count >= 4
            && displayName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    // MARK: Shared pieces

    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                Text(l10n.authBack)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(FluxColors.blue)
        }
        .buttonStyle(ScaleButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func resetToUsername() {
        step = .username
        password = ""
        errorText = nil
    }

    private func checkUsername() {
        guard usernameValid, !busy else { return }
        busy = true
        errorText = nil
        let trimmed = username
        Task {
            let found = await backend.lookupUsername(trimmed)
            busy = false
            if let found {
                step = .login(found)
            } else {
                step = .register(trimmed)
            }
        }
    }

    private func login(_ user: FluxUser) {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            do {
                let loggedIn = try await backend.loginSmart(username: user.username ?? username, password: password)
                saveToVault(loggedIn, password: password)
                await backend.saveBiometricLogin(user.username ?? username)
                busy = false
            } catch {
                busy = false
                errorText = error.localizedDescription == FluxError.wrongPassword.message
                    ? l10n.authWrongPassword
                    : l10n.authUserNotFound
            }
        }
    }

    private func register() {
        guard registerValid, !busy else { return }
        busy = true
        errorText = nil
        Task {
            do {
                let user = try await backend.registerSmart(
                    username: username,
                    email: email,
                    password: password,
                    displayName: displayName
                )
                saveToVault(user, password: password)
                await backend.saveBiometricLogin(username)
                busy = false
            } catch {
                busy = false
                errorText = error.localizedDescription
            }
        }
    }

    private func saveToVault(_ user: FluxUser, password: String) {
        accountManager.addAccount(StoredAccount(
            fluxId: user.fluxId,
            username: user.username ?? username,
            displayName: user.name,
            avatarPath: user.avatarPath,
            sessionToken: UUID().uuidString,
            lastLoginAtMs: Int(Date().timeIntervalSince1970 * 1000),
            password: rememberMe ? password : nil,
            rememberMe: rememberMe
        ))
    }

    private func prefillRemembered() {
        guard case .username = step,
              let remembered = accountManager.lastRemembered,
              let password = remembered.password else { return }
        username = remembered.username
        self.password = password
        rememberMe = true
        Task {
            if let found = await backend.lookupUsername(remembered.username) {
                step = .login(found)
            }
        }
    }

    // MARK: Biometrics

    private func biometricsAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    private func authenticateBiometric(username: String) {
        let context = LAContext()
        context.localizedCancelTitle = l10n.cancel
        do {
            try context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Flux"
            ) { [weak backend] success, _ in
                Task { @MainActor in
                    guard success, let backend else { return }
                    Haptics.success()
                    if let user = try? await backend.loginBiometric(username: username) {
                        accountManager.addAccount(StoredAccount(
                            fluxId: user.fluxId,
                            username: user.username ?? username,
                            displayName: user.name,
                            sessionToken: UUID().uuidString,
                            lastLoginAtMs: Int(Date().timeIntervalSince1970 * 1000)
                        ))
                    }
                }
            }
        } catch {
            // Biometrics unavailable — the PIN/password path is used.
        }
    }
}

/// Password field with the Flux styling (secure entry).
struct FluxSecureField: View {
    @Binding var text: String
    let hint: String
    var autofocus = false
    var onSubmitted: (() -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        SecureField(hint, text: $text)
            .submitLabel(.done)
            .focused($focused)
            .foregroundStyle(FluxColors.textPrimary)
            .font(.system(size: 17, weight: .medium))
            .onSubmit { onSubmitted?() }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(FluxColors.surfaceGray)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(focused ? FluxColors.blue : .clear, lineWidth: 1.5)
            )
            .onAppear {
                if autofocus {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        focused = true
                    }
                }
            }
    }
}
