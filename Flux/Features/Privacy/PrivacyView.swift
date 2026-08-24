import SwiftUI
import UIKit

/// Privacy screen: devices entry, privacy mode hero, visibility toggles,
/// content protection, app lock, fatal messages, premium tools.
struct PrivacyView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n
    @EnvironmentObject var lock: LockController

    @State private var showSetPin = false
    @State private var showAutoDeleteSheet = false
    @State private var showAdvancedSheet = false
    @State private var showPremiumSheet = false
    @State private var pushSupportChat = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                devicesTile
                privacyModeCard
                FluxSectionTitle(text: l10n.visibility)
                VStack(spacing: 0) {
                    switchTile(l10n.showOnlineStatus, icon: "circle.fill", color: FluxColors.online, keyPath: \.showOnline)
                    switchTile(l10n.lastVisit, icon: "clock.fill", showDivider: true, keyPath: \.showLastSeen)
                    switchTile(l10n.readReceipts, icon: "checkmark.double", showDivider: true, keyPath: \.readReceipts)
                    switchTile(l10n.hideTypingStatus, icon: "keyboard", color: FluxColors.violet, background: FluxColors.violetSoft, keyPath: \.hideTyping)
                }
                .settingsCard()

                FluxSectionTitle(text: l10n.contentProtection)
                VStack(spacing: 0) {
                    switchTile(l10n.blockScreenshots, icon: "camera.on.rectangle", color: FluxColors.danger, background: FluxColors.danger.opacity(0.1), keyPath: \.blockScreenshots, onChanged: { enabled in
                        // iOS has no FLAG_SECURE equivalent; instead we
                        // detect screenshots and alert the security bot.
                        ScreenshotMonitor.shared.setEnabled(enabled)
                    })
                    switchTile(l10n.forbidForwarding, icon: "hand.raised.fill", color: FluxColors.danger, background: FluxColors.danger.opacity(0.1), showDivider: true, keyPath: \.forbidForward)
                }
                .settingsCard()

                FluxSectionTitle(text: l10n.appLock)
                VStack(spacing: 0) {
                    switchTile(l10n.appLock, subtitle: l10n.appLockDesc, icon: "lock.fill", color: FluxColors.violet, background: FluxColors.violetSoft, keyPath: \.appLockEnabled, onChanged: { enabled in
                        if enabled && backend.privacy.appLockPinHash == nil {
                            showSetPin = true
                        } else if !enabled {
                            lock.unlock()
                        }
                    })
                    switchTile(l10n.appLockBiometrics, subtitle: l10n.appLockBiometricsDesc, icon: "faceid", color: FluxColors.online, background: FluxColors.online.opacity(0.12), showDivider: true, keyPath: \.appLockBiometrics)
                    FluxSettingsTile(icon: "key.fill", title: "Сменить PIN-код", iconColor: FluxColors.warning, iconBackground: FluxColors.warning.opacity(0.13)) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(FluxColors.textTertiary)
                    } onTap: {
                        showSetPin = true
                    }
                    .padding(.horizontal, 8)
                    .overlay(alignment: .top) { Divider().padding(.leading, 62) }
                }
                .settingsCard()

                FluxSectionTitle(text: l10n.fatalMessages.uppercased())
                VStack(spacing: 0) {
                    switchTile(l10n.fatalMessages, subtitle: l10n.fatalMessagesDesc, icon: "flame.fill", color: FluxColors.warning, background: FluxColors.warning.opacity(0.13), keyPath: \.fatalMessages)
                    FluxSettingsTile(icon: "timer", title: l10n.autoDelete, subtitle: l10n.autoDeleteDesc) {
                        HStack(spacing: 6) {
                            Text(backend.privacy.autoDelete.labelRu)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(FluxColors.blue)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13))
                                .foregroundStyle(FluxColors.textTertiary)
                        }
                    } onTap: {
                        showAutoDeleteSheet = true
                    }
                    .padding(.horizontal, 8)
                    .overlay(alignment: .top) { Divider().padding(.leading, 62) }
                }
                .settingsCard()

                advancedCard
            }
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 32, trailing: 8))
        }
        .background(FluxColors.background.ignoresSafeArea())
        .navigationTitle(l10n.privacy)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSetPin) { SetPinSheet() }
        .sheet(isPresented: $showAutoDeleteSheet) { autoDeleteSheet }
        .sheet(isPresented: $showAdvancedSheet) { advancedSheet }
        .sheet(isPresented: $showPremiumSheet) {
            PremiumSheet {
                Task {
                    _ = await backend.openChatWithUser(backend.ensureSupportUser())
                    pushSupportChat = true
                }
            }
            .presentationDetents([.fraction(0.72), .large])
        }
        .navigationDestination(isPresented: $pushSupportChat) {
            ChatView(chatId: backend.chatWithPeer(FluxUser.supportId)?.id ?? "")
        }
        .onAppear {
            ScreenshotMonitor.shared.attach(backend: backend)
        }
    }

    // MARK: Tiles

    private var devicesTile: some View {
        NavigationLink(value: Route.devices) {
            FluxSettingsTile(icon: "laptopcomputer.and.iphone", title: l10n.devices, subtitle: l10n.devicesDesc) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(FluxColors.textTertiary)
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FluxColors.surface)
        )
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 6, trailing: 8))
    }

    private var privacyModeCard: some View {
        let isOn = backend.privacy.privacyMode
        return Button {
            Haptics.medium()
            var privacy = backend.privacy
            privacy.privacyMode.toggle()
            Task { await backend.updatePrivacy(privacy) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(Color.white.opacity(0.2)) : AnyShapeStyle(FluxColors.gradient))
                        .frame(width: 46, height: 46)
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.privacyMode)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isOn ? .white : FluxColors.textPrimary)
                    Text(l10n.privacyModeDesc)
                        .font(.system(size: 13))
                        .foregroundStyle(isOn ? Color.white.opacity(0.85) : FluxColors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(isOn ? "✓" : l10n.configure)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isOn ? .white : FluxColors.blue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(isOn ? Color.white.opacity(0.22) : FluxColors.surfaceGray)
                    )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(FluxColors.gradient) : AnyShapeStyle(FluxColors.surface))
            )
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.98))
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
    }

    private func switchTile(
        _ title: String,
        subtitle: String? = nil,
        icon: String,
        color: Color = FluxColors.blue,
        background: Color = FluxColors.blueSoft,
        showDivider: Bool = false,
        keyPath: WritableKeyPath<PrivacySettings, Bool>,
        onChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        FluxSettingsTile(
            icon: icon,
            title: title,
            subtitle: subtitle,
            iconColor: color,
            iconBackground: background,
            showDivider: showDivider
        ) {
            FluxSwitch(isOn: backend.privacy[keyPath: keyPath]) { value in
                var privacy = backend.privacy
                privacy[keyPath: keyPath] = value
                Task { await backend.updatePrivacy(privacy) }
                onChanged?(value)
            }
        }
        .padding(.horizontal, 8)
    }

    private var advancedCard: some View {
        Button {
            showAdvancedSheet = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 46, height: 46)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advanced")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("IP-маскировка, стелс-режим и другие инструменты доступны с Premium.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(backend.me?.isPremium == true ? FluxColors.online : FluxColors.violet)
                    Text("Premium")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(FluxColors.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(FluxColors.gradient)
            )
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.98))
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
    }

    // MARK: Sheets

    private var autoDeleteSheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            Text(l10n.autoDelete)
                .font(.system(size: 18, weight: .heavy))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 18, leading: 20, bottom: 10, trailing: 20))
            ForEach(AutoDelete.allCases, id: \.self) { option in
                Button {
                    Haptics.selection()
                    var privacy = backend.privacy
                    privacy.autoDelete = option
                    Task { await backend.updatePrivacy(privacy) }
                    showAutoDeleteSheet = false
                } label: {
                    FluxSettingsTile(
                        icon: "timer",
                        title: option.labelRu,
                        iconColor: backend.privacy.autoDelete == option ? FluxColors.blue : FluxColors.textTertiary,
                        iconBackground: backend.privacy.autoDelete == option ? FluxColors.blueSoft : FluxColors.surfaceGray
                    ) {
                        if backend.privacy.autoDelete == option {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 21))
                                .foregroundStyle(FluxColors.online)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 12)
        }
        .background(Material.ultraThinMaterial)
        .presentationDetents([.medium, .large])
    }

    private var advancedSheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            Text(l10n.advancedPrivacy)
                .font(.system(size: 18, weight: .heavy))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 18, leading: 20, bottom: 10, trailing: 20))
            FluxSettingsTile(icon: "key.horizontal.fill", title: "IP-маскировка", subtitle: backend.me?.isPremium == true ? "Доступно" : "Требуется Premium") {
                statusIcon(available: backend.me?.isPremium == true)
            }
            .padding(.horizontal, 8)
            FluxSettingsTile(icon: "eye.slash.fill", title: "Стелс-режим", subtitle: backend.me?.isPremium == true ? "Доступно" : "Требуется Premium", iconColor: FluxColors.violet, iconBackground: FluxColors.violetSoft) {
                statusIcon(available: backend.me?.isPremium == true)
            }
            .padding(.horizontal, 8)
            if backend.me?.isPremium != true {
                FluxButton(title: "Подробнее о Flux Premium") {
                    showAdvancedSheet = false
                    showPremiumSheet = true
                }
                .padding(20)
            }
            Spacer(minLength: 12)
        }
        .background(Material.ultraThinMaterial)
        .presentationDetents([.medium])
    }

    private func statusIcon(available: Bool) -> some View {
        Image(systemName: available ? "checkmark.circle.fill" : "lock.fill")
            .font(.system(size: available ? 21 : 17))
            .foregroundStyle(available ? FluxColors.online : FluxColors.textTertiary)
    }
}

/// «Установить код» sheet — two masked 4-digit fields.
struct SetPinSheet: View {
    @EnvironmentObject var backend: LocalBackend
    @Environment(\.dismiss) private var dismiss

    @State private var pin = ""
    @State private var confirm = ""
    @State private var mismatch = false

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            Text("Установить код")
                .font(.system(size: 18, weight: .heavy))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            FluxTextField(text: $pin, hint: "Введите код", keyboard: .numberPad, maxLength: 4)
                .padding(.horizontal, 20)
            FluxTextField(text: $confirm, hint: "Повторите код", keyboard: .numberPad, maxLength: 4)
                .padding(.horizontal, 20)

            Text(mismatch ? "Коды не совпадают" : " ")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FluxColors.danger)
                .frame(height: 20)

            FluxButton(title: "Сохранить", enabled: pin.count == 4 && confirm.count == 4 && pin == confirm) {
                Haptics.success()
                var privacy = backend.privacy
                privacy.appLockPinHash = PinHash.hash(pin)
                privacy.appLockEnabled = true
                Task { await backend.updatePrivacy(privacy) }
                dismiss()
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 16)
        }
        .background(FluxColors.background.ignoresSafeArea())
        .presentationDetents([.height(380)])
        .onChange(of: confirm) { newValue in
            let filtered = newValue.filter { $0.isNumber }
            confirm = String(filtered.prefix(4))
            mismatch = false
        }
        .onChange(of: pin) { newValue in
            pin = String(newValue.filter { $0.isNumber }.prefix(4))
            mismatch = false
        }
        .onAppear {
            pin = ""
            confirm = ""
        }
    }
}

// MARK: - Screenshot monitor

/// iOS cannot block screenshots the way Android's FLAG_SECURE does; when
/// the toggle is on we listen for UIApplication.userDidTakeScreenshotNotification
/// and post a warning into the security-bot chat.
@MainActor
final class ScreenshotMonitor: ObservableObject {
    static let shared = ScreenshotMonitor()

    private weak var backend: LocalBackend?
    private var enabled = false

    func attach(backend: LocalBackend) {
        self.backend = backend
        setEnabled(backend.privacy.blockScreenshots)
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if value {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(screenshotTaken),
                name: UIApplication.userDidTakeScreenshotNotification,
                object: nil
            )
        } else {
            NotificationCenter.default.removeObserver(
                self,
                name: UIApplication.userDidTakeScreenshotNotification,
                object: nil
            )
        }
    }

    @objc private func screenshotTaken() {
        Task { @MainActor in
            guard let backend else { return }
            let bot = backend.ensureSecurityBot()
            let chat = await backend.openChatWithUser(bot)
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            let message = FluxMessage(
                id: UUID().uuidString,
                chatId: chat.id,
                senderId: FluxUser.systemSecurityBotId,
                text: "⚠️ Зафиксирована попытка снимка экрана в \(formatTime(nowMs)).",
                sentAtMs: nowMs,
                isSystemMessage: true
            )
            backend.ingestScreenshotWarning(message)
        }
    }
}
