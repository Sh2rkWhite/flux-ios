import SwiftUI
import LocalAuthentication

/// PIN / biometry lock screen. Shown at cold start and every foreground
/// return while app-lock is enabled.
struct LockScreenView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var lock: LockController
    @EnvironmentObject var l10n: FluxL10n

    @State private var entered = ""
    @State private var errorVisible = false
    @State private var shakeOffset: CGFloat = 0

    private var pinHash: String? { backend.privacy.appLockPinHash }
    private var useBiometrics: Bool { backend.privacy.appLockBiometrics }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            FluxLogoMark(size: 64, animate: true)
            Text("Flux")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(FluxColors.textPrimary)
                .padding(.top, 18)
            Text(l10n.appLockEnterPin)
                .font(.system(size: 15))
                .foregroundStyle(FluxColors.textSecondary)
                .padding(.top, 6)

            pinDots
                .offset(x: shakeOffset)
                .padding(.top, 26)

            Text(errorVisible ? l10n.appLockWrong : " ")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FluxColors.danger)
                .frame(height: 20)
                .padding(.top, 10)

            keypad
                .padding(.top, 26)

            if biometricsAvailable() {
                Button {
                    Haptics.light()
                    promptBiometrics()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                            .font(.system(size: 17))
                        Text(l10n.authBiometricLogin)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(FluxColors.blue)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.top, 22)
            }
            Spacer(minLength: 28)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .background(FluxColors.background.ignoresSafeArea())
        .onAppear {
            if useBiometrics, biometricsAvailable() {
                promptBiometrics()
            }
        }
    }

    private var pinDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .strokeBorder(entered.count > i ? FluxColors.blue : Color(hex: 0xD5D9E4), lineWidth: 2)
                    .background(
                        Circle().fill(entered.count > i ? FluxColors.blue : .clear)
                    )
                    .frame(width: 14, height: 14)
            }
        }
        .environment(\.colorScheme, .light)
    }

    private var keypad: some View {
        VStack(spacing: 7) {
            keyRow(["1", "2", "3"])
            keyRow(["4", "5", "6"])
            keyRow(["7", "8", "9"])
            HStack(spacing: 18) {
                if biometricsAvailable() {
                    keyTile {
                        Image(systemName: "faceid")
                            .font(.system(size: 22))
                            .foregroundStyle(FluxColors.blue)
                    } action: {
                        promptBiometrics()
                    }
                } else {
                    Color.clear.frame(width: 76, height: 62)
                }
                digitKey("0")
                keyTile {
                    Image(systemName: "delete.left")
                        .font(.system(size: 20))
                        .foregroundStyle(FluxColors.blue)
                } action: {
                    Haptics.light()
                    if !entered.isEmpty {
                        entered.removeLast()
                    }
                    errorVisible = false
                }
            }
        }
    }

    private func keyRow(_ digits: [String]) -> some View {
        HStack(spacing: 18) {
            ForEach(digits, id: \.self) { digitKey($0) }
        }
    }

    private func digitKey(_ digit: String) -> some View {
        keyTile {
            Text(digit)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(FluxColors.textPrimary)
        } action: {
            appendDigit(digit)
        }
    }

    private func keyTile<Content: View>(@ViewBuilder content: () -> Content, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content()
                .frame(width: 76, height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(FluxColors.surface)
                        .shadow(color: Color(hex: 0x1A2340).opacity(0.06), radius: 10, y: 4)
                )
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.92))
    }

    private func appendDigit(_ digit: String) {
        Haptics.light()
        guard entered.count < 4 else { return }
        entered.append(digit)
        guard entered.count == 4 else { return }

        if let pinHash, PinHash.verify(entered, stored: pinHash) {
            Haptics.success()
            entered = ""
            errorVisible = false
            lock.unlock()
        } else {
            Haptics.medium()
            errorVisible = true
            entered = ""
            shake()
        }
    }

    private func shake() {
        withAnimation(.easeInOut(duration: 0.04)) { shakeOffset = 9 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeInOut(duration: 0.04)) { shakeOffset = -9 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeInOut(duration: 0.04)) { shakeOffset = 5 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeInOut(duration: 0.2)) { shakeOffset = 0 }
        }
    }

    private func biometricsAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    private func promptBiometrics() {
        let context = LAContext()
        context.localizedCancelTitle = l10n.cancel
        do {
            try context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Flux"
            ) { success, _ in
                Task { @MainActor in
                    if success {
                        Haptics.success()
                        lock.unlock()
                    }
                }
            }
        } catch {
            // Biometrics unavailable — PIN entry remains.
        }
    }
}
