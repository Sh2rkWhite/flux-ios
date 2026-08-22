import SwiftUI

/// «Мой QR» — the user's personal QR code with the safe public deep link.
struct MyQRView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    @State private var toast: Toast?
    @State private var showScanner = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                FluxAvatarView(user: backend.me, size: 72)
                    .overlay(Circle().stroke(FluxColors.surface, lineWidth: 3))

                VStack(spacing: 4) {
                    Text(backend.me?.name ?? "")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(FluxColors.textPrimary)
                    if let username = backend.me?.username {
                        Text("@\(username)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FluxColors.blue)
                    }
                }

                QRCodeView(fluxId: backend.me?.fluxId ?? "FLX-")

                Text("Наведите камеру другого устройства на этот код — откроется ваш профиль")
                    .font(.system(size: 13))
                    .foregroundStyle(FluxColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = QRCodeGenerator.deepLink(fluxId: backend.me?.fluxId ?? "")
                        Haptics.success()
                        toast = Toast(text: "Ссылка скопирована")
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                            Text("Скопировать ссылку")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FluxColors.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(FluxColors.blueSoft)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())

                    ShareLink(item: QRCodeGenerator.deepLink(fluxId: backend.me?.fluxId ?? "")) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Поделиться")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(FluxColors.gradient)
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 24)
        }
        .background(FluxColors.background.ignoresSafeArea())
        .navigationTitle("Мой QR")
        .navigationBarTitleDisplayMode(.inline)
        .fluxToast($toast)
    }
}

/// «Сканировать QR» — camera scanner. A valid Flux QR opens the user's
/// profile; anything else shows «QR-код недействителен».
struct QRScannerView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    @State private var isScanningEnabled = true
    @State private var scannedUserId: String?
    @State private var invalidToast: Toast?

    var body: some View {
        ZStack(alignment: .top) {
            QRScannerController(onScanned: handleScan, isScanningEnabled: $isScanningEnabled)
                .ignoresSafeArea()

            VStack {
                Text("Наведите камеру на QR-код")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(.top, 16)

                // Finder frame
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.8), lineWidth: 3)
                    .frame(width: 240, height: 240)
                    .padding(.top, 60)

                Spacer()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Сканировать QR")
        .navigationBarTitleDisplayMode(.inline)
        .fluxToast($invalidToast)
        .navigationDestination(isPresented: Binding(
            get: { scannedUserId != nil },
            set: { if !$0 { scannedUserId = nil } }
        )) {
            if let userId = scannedUserId {
                UserProfileView(userId: userId)
            }
        }
    }

    private func handleScan(_ payload: String) {
        guard isScanningEnabled else { return }
        isScanningEnabled = false
        Haptics.success()

        guard let fluxId = QRCodeParser.fluxId(from: payload) else {
            invalidToast = Toast(text: "QR-код недействителен", isError: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                isScanningEnabled = true
            }
            return
        }

        // Resolve the FluxID to a known user (remote users are registered
        // on the fly) and push the profile.
        let user = backend.registerExternalUser(fluxId)
        scannedUserId = user.id
        isScanningEnabled = true
    }
}
