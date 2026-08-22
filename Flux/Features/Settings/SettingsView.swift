import SwiftUI

/// Settings screen: account, notifications, general — plus the new
/// profile-system entries (Уровень и активность, Flux Coins, Магазин
/// бейджей, Marketplace, QR).
struct SettingsView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    @State private var editField: EditField?

    enum EditField: String, Identifiable {
        case name, status
        var id: String { rawValue }

        var title: String {
            switch self {
            case .name: return "Имя"
            case .status: return "Статус"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                FluxSectionTitle(text: l10n.account)
                VStack(spacing: 0) {
                    NavigationLink(value: Route.userProfile(userId: backend.me?.id ?? "")) {
                        FluxSettingsTile(icon: "person.fill", title: l10n.myProfile, subtitle: backend.me?.name)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(FluxColors.separator).padding(.leading, 62)
                    FluxSettingsTile(icon: "person.text.rectangle", title: l10n.name, subtitle: backend.me?.name) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(FluxColors.textTertiary)
                    } onTap: {
                        editField = .name
                    }
                    .padding(.horizontal, 8)
                    Divider().overlay(FluxColors.separator).padding(.leading, 62)
                    FluxSettingsTile(icon: "info.circle.fill", title: l10n.status, subtitle: backend.me?.status, iconColor: FluxColors.violet, iconBackground: FluxColors.violetSoft) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(FluxColors.textTertiary)
                    } onTap: {
                        editField = .status
                    }
                    .padding(.horizontal, 8)
                }
                .settingsCard()

                FluxSectionTitle(text: "Профиль и активность")
                VStack(spacing: 0) {
                    NavigationLink(value: Route.levelActivity) {
                        FluxSettingsTile(
                            icon: "chart.bar.fill",
                            title: "Уровень и активность",
                            subtitle: "Level \(backend.myProfile.level) · \(backend.myProfile.activityPoints) XP",
                            iconColor: FluxColors.violet,
                            iconBackground: FluxColors.violetSoft,
                            showDivider: true
                        ) { chevron }
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: Route.fluxCoins) {
                        FluxSettingsTile(
                            icon: "dollarsign.circle.fill",
                            title: "Flux Coins",
                            subtitle: "\(backend.fluxCoins) монет",
                            iconColor: FluxColors.warning,
                            iconBackground: FluxColors.warning.opacity(0.13),
                            showDivider: true
                        ) { chevron }
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: Route.badgeShop) {
                        FluxSettingsTile(
                            icon: "rosette",
                            title: "Магазин бейджей",
                            subtitle: "Бейджи за Flux Coins",
                            showDivider: true
                        ) { chevron }
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: Route.marketplace) {
                        FluxSettingsTile(
                            icon: "storefront.fill",
                            title: "Marketplace",
                            subtitle: "Покупка и продажа username",
                            iconColor: FluxColors.online,
                            iconBackground: FluxColors.online.opacity(0.12),
                            showDivider: true
                        ) { chevron }
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: Route.myQR) {
                        FluxSettingsTile(
                            icon: "qrcode",
                            title: "Мой QR-код",
                            iconColor: FluxColors.violet,
                            iconBackground: FluxColors.violetSoft
                        ) { chevron }
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                }
                .settingsCard()

                FluxSectionTitle(text: l10n.notifications.uppercased())
                VStack(spacing: 0) {
                    FluxSettingsTile(icon: "bell.fill", title: l10n.notifications, iconColor: FluxColors.warning, iconBackground: FluxColors.warning.opacity(0.13), showDivider: true) {
                        FluxSwitch(isOn: backend.prefs.notifications) { value in
                            var prefs = backend.prefs
                            prefs.notifications = value
                            Task { await backend.updatePrefs(prefs) }
                        }
                    }
                    .padding(.horizontal, 8)
                    FluxSettingsTile(icon: "eye.fill", title: l10n.messagePreview, showDivider: true) {
                        FluxSwitch(isOn: backend.prefs.messagePreview) { value in
                            var prefs = backend.prefs
                            prefs.messagePreview = value
                            Task { await backend.updatePrefs(prefs) }
                        }
                    }
                    .padding(.horizontal, 8)
                    FluxSettingsTile(icon: "speaker.wave.2.fill", title: l10n.sounds, iconColor: FluxColors.online, iconBackground: FluxColors.online.opacity(0.12)) {
                        FluxSwitch(isOn: backend.prefs.sounds) { value in
                            var prefs = backend.prefs
                            prefs.sounds = value
                            Task { await backend.updatePrefs(prefs) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .settingsCard()
            }
            .padding(.bottom, 32)
        }
        .background(FluxColors.background.ignoresSafeArea())
        .navigationTitle(l10n.settings)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editField) { field in
            EditFieldSheet(field: field)
                .presentationDetents([.height(260)])
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13))
            .foregroundStyle(FluxColors.textTertiary)
    }
}

extension View {
    func settingsCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FluxColors.surface)
        )
        .padding(.horizontal, 8)
    }
}

/// Sheet for editing a single profile field (name / status).
struct EditFieldSheet: View {
    @EnvironmentObject var backend: LocalBackend
    @Environment(\.dismiss) private var dismiss

    let field: SettingsView.EditField

    @State private var value = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            Text(field.title)
                .font(.system(size: 18, weight: .heavy))
                .frame(maxWidth: .infinity, alignment: .leading)
            FluxTextField(text: $value, hint: field.title, autofocus: true)
            FluxButton(title: "Сохранить", enabled: !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task {
                    switch field {
                    case .name:
                        await backend.updateMe(name: trimmed)
                    case .status:
                        await backend.updateMe(status: trimmed)
                    }
                    dismiss()
                }
            }
            Spacer(minLength: 16)
        }
        .padding(.horizontal, 20)
        .background(FluxColors.background.ignoresSafeArea())
        .onAppear {
            value = field == .name ? (backend.me?.name ?? "") : (backend.me?.status ?? "")
        }
    }
}
