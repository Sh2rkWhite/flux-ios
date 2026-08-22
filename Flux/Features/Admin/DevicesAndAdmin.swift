import SwiftUI

/// Active devices / sessions list with revoke actions.
struct DevicesView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    @State private var revokeTarget: DeviceSession?
    @State private var showRevokeAll = false

    private var activeSessions: [DeviceSession] {
        backend.me?.sessions.filter { !$0.revoked }.sorted { $0.loginAtMs > $1.loginAtMs } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(FluxColors.gradient)
                            .frame(width: 44, height: 44)
                        Image(systemName: "laptopcomputer.and.iphone")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.devices)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(FluxColors.textPrimary)
                        Text(l10n.devicesDesc)
                            .font(.system(size: 13))
                            .foregroundStyle(FluxColors.textSecondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(FluxColors.surface)
                )
                .padding(EdgeInsets(top: 8, leading: 8, bottom: 6, trailing: 8))

                if activeSessions.isEmpty {
                    Text(l10n.noActiveSessions)
                        .font(.system(size: 14))
                        .foregroundStyle(FluxColors.textSecondary)
                        .padding(.top, 32)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(activeSessions.enumerated()), id: \.element.id) { index, session in
                            if index > 0 {
                                Divider().overlay(FluxColors.separator).padding(.leading, 64)
                            }
                            SessionRow(
                                session: session,
                                isCurrent: session.id == backend.currentSessionId
                            ) {
                                Haptics.medium()
                                revokeTarget = session
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(FluxColors.surface)
                    )
                    .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))

                    if activeSessions.contains(where: { $0.id != backend.currentSessionId }) {
                        Button {
                            Haptics.medium()
                            showRevokeAll = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 17))
                                Text(l10n.terminateAll)
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(FluxColors.danger)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(FluxColors.danger.opacity(0.1))
                                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(FluxColors.danger.opacity(0.25), lineWidth: 1))
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .padding(EdgeInsets(top: 10, leading: 16, bottom: 16, trailing: 16))
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(FluxColors.background.ignoresSafeArea())
        .navigationTitle(l10n.devices)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(l10n.terminateTitle, isPresented: Binding(
            get: { revokeTarget != nil },
            set: { if !$0 { revokeTarget = nil } }
        ), titleVisibility: .visible) {
            Button(l10n.terminate, role: .destructive) {
                if let target = revokeTarget {
                    let id = target.id
                    Task { await backend.revokeSession(id) }
                }
                revokeTarget = nil
            }
            Button(l10n.cancel, role: .cancel) { revokeTarget = nil }
        } message: {
            Text(l10n.terminateBody)
        }
        .confirmationDialog(l10n.terminateAll, isPresented: $showRevokeAll, titleVisibility: .visible) {
            Button(l10n.terminate, role: .destructive) {
                Task { await backend.revokeAllOtherSessions() }
            }
            Button(l10n.cancel, role: .cancel) {}
        } message: {
            Text(l10n.terminateAllConfirm)
        }
    }
}

private struct SessionRow: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    let session: DeviceSession
    let isCurrent: Bool
    let onRevoke: () -> Void

    private var platformInfo: (icon: String, color: Color, background: Color) {
        switch session.platform?.lowercased() {
        case "android":
            return ("a.circle.fill", FluxColors.online, FluxColors.online.opacity(0.12))
        case "ios":
            return ("iphone", FluxColors.blue, FluxColors.blueSoft)
        case "windows":
            return ("desktopcomputer", FluxColors.violet, FluxColors.violetSoft)
        case "macos":
            return ("laptopcomputer", FluxColors.warning, FluxColors.warning.opacity(0.13))
        case "linux":
            return ("laptopcomputer", FluxColors.textSecondary, FluxColors.surfaceGray)
        default:
            return ("iphone.gen3", Color(hex: 0x8A8F98), FluxColors.surfaceGray)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(platformInfo.background)
                    .frame(width: 40, height: 40)
                Image(systemName: platformInfo.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(platformInfo.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.deviceName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FluxColors.textPrimary)
                        .lineLimit(1)
                    if isCurrent {
                        Text(l10n.thisDevice)
                            .font(.system(size: 10.5, weight: .heavy))
                            .foregroundStyle(FluxColors.online)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(FluxColors.online.opacity(0.12)))
                    }
                }
                Text(formatCallTime(session.loginAtMs))
                    .font(.system(size: 12.5))
                    .foregroundStyle(FluxColors.textSecondary)
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                        .foregroundStyle(FluxColors.textTertiary)
                    Text(session.ip ?? "—")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(FluxColors.textTertiary)
                }
            }
            Spacer()
            if !isCurrent {
                Button(action: onRevoke) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 17))
                        .foregroundStyle(FluxColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
    }
}

/// Admin panel: statistics, Flux Coins granting, user list with
/// promote/demote (remote mode only).
struct AdminPanelView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    @State private var amountText = ""
    @State private var toast: Toast?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                statsCard
                FluxSectionTitle(text: "FLUX COINS")
                coinsCard
                FluxSectionTitle(text: l10n.adminUsers.uppercased())
                usersCard
            }
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 40, trailing: 8))
        }
        .background(FluxColors.background.ignoresSafeArea())
        .navigationTitle(l10n.adminPanel)
        .navigationBarTitleDisplayMode(.inline)
        .fluxToast($toast)
    }

    private var statsCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 40, height: 40)
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
                Text(l10n.adminStats)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer()
            }
            HStack(spacing: 10) {
                statTile(value: "\(backend.directory.count)", label: l10n.adminUsers)
                statTile(value: "\(adminCount)", label: l10n.adminRole)
                statTile(value: "\(premiumCount)", label: "Premium")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FluxColors.gradient)
        )
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.18))
        )
    }

    private var adminCount: Int {
        backend.directory.filter { $0.isAdmin }.count + (backend.isAdmin ? 1 : 0)
    }

    private var premiumCount: Int {
        backend.directory.filter { $0.isPremium }.count
    }

    private var coinsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("🪙")
                    .font(.system(size: 20))
                Text("Мой баланс: \(backend.fluxCoins) монет")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FluxColors.warning)
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FluxColors.warning.opacity(0.08))
            )

            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle")
                    .foregroundStyle(FluxColors.warning)
                TextField("Количество монет", text: $amountText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 15))
                    .foregroundStyle(FluxColors.textPrimary)
                    .onChange(of: amountText) { newValue in
                        amountText = String(newValue.filter { $0.isNumber }.prefix(6))
                    }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(FluxColors.separator, lineWidth: 1)
            )

            Button {
                grantCoins()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Выдать себе")
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FluxColors.warning)
                )
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FluxColors.surface)
        )
        .padding(EdgeInsets(top: 0, leading: 8, bottom: 8, trailing: 8))
    }

    private func grantCoins() {
        guard let amount = Int(amountText), amount > 0 else { return }
        Task {
            await backend.awardCoinsWithTransaction(
                amount: amount,
                type: .bonus,
                description: "Начисление администратора"
            )
            amountText = ""
            toast = Toast(text: "Выдано \(amount) монет! Баланс: \(backend.fluxCoins)")
        }
    }

    private var usersCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(backend.directory.enumerated()), id: \.element.id) { index, user in
                if index > 0 {
                    Divider().overlay(FluxColors.separator).padding(.leading, 64)
                }
                HStack(spacing: 12) {
                    FluxAvatarView(user: user, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(FluxColors.textPrimary)
                            .lineLimit(1)
                        Text(user.username.map { "@\($0)" } ?? user.fluxId)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(FluxColors.textSecondary)
                    }
                    Spacer()
                    if user.isAdmin {
                        Text(l10n.adminRole)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(FluxColors.online)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(FluxColors.online.opacity(0.12)))
                    }
                }
                .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FluxColors.surface)
        )
        .padding(EdgeInsets(top: 0, leading: 8, bottom: 8, trailing: 8))
    }
}
