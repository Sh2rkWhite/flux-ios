import SwiftUI

/// Settings screen: account, notifications, general — plus the new
/// profile-system entries (Уровень и активность, Flux Coins, Магазин
/// бейджей, Marketplace, QR).
struct SettingsView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n
    @EnvironmentObject var theme: ThemeController

    @State private var editField: EditField?
    @State private var showLanguageSheet = false
    @State private var showThemeSheet = false

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
                    NavigationLink(value: Route.coinsBot(sendTo: nil, sendAmount: nil)) {
                        FluxSettingsTile(
                            icon: "dollarsign.circle.fill",
                            title: "Flux Coins",
                            subtitle: "\(backend.fluxCoins) \(pluralRu(backend.fluxCoins, "монета", "монеты", "монет")) · @FluxCoinsBot",
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

                FluxSectionTitle(text: "Оформление и приватность")
                VStack(spacing: 0) {
                    NavigationLink(value: Route.privacy) {
                        FluxSettingsTile(icon: "lock.fill", title: l10n.privacy, iconColor: FluxColors.violet, iconBackground: FluxColors.violetSoft, showDivider: true) { chevron }
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    FluxSettingsTile(icon: "paintpalette.fill", title: l10n.theme, iconColor: FluxColors.violet, iconBackground: FluxColors.violetSoft, showDivider: true) {
                        HStack(spacing: 6) {
                            Text(currentThemeLabel)
                                .font(.system(size: 14))
                                .foregroundStyle(FluxColors.textSecondary)
                            chevron
                        }
                    } onTap: {
                        showThemeSheet = true
                    }
                    .padding(.horizontal, 8)
                    FluxSettingsTile(icon: "globe", title: l10n.languageTitle, iconColor: FluxColors.online, iconBackground: FluxColors.online.opacity(0.12)) {
                        HStack(spacing: 6) {
                            Text(l10n.isRu ? "Русский" : "English")
                                .font(.system(size: 14))
                                .foregroundStyle(FluxColors.textSecondary)
                            chevron
                        }
                    } onTap: {
                        showLanguageSheet = true
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
        .sheet(isPresented: $showThemeSheet) { themeSheet }
        .sheet(isPresented: $showLanguageSheet) { languageSheet }
    }

    private var currentThemeLabel: String {
        switch theme.mode {
        case .light: return l10n.themeLight
        case .dark: return l10n.themeDark
        case .system: return l10n.themeSystem
        }
    }

    private var themeSheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            Text(l10n.theme)
                .font(.system(size: 18, weight: .heavy))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 18, leading: 20, bottom: 10, trailing: 20))
            themeOption(l10n.themeLight, mode: .light, icon: "sun.max.fill")
            themeOption(l10n.themeDark, mode: .dark, icon: "moon.fill")
            themeOption(l10n.themeSystem, mode: .system, icon: "circle.lefthalf.filled")
            Spacer(minLength: 12)
        }
        .background(FluxColors.background.ignoresSafeArea())
        .presentationDetents([.height(320)])
    }

    private func themeOption(_ title: String, mode: ThemeController.Mode, icon: String) -> some View {
        Button {
            Haptics.selection()
            theme.setMode(mode)
            var prefs = backend.prefs
            prefs.themeMode = theme.storedValue
            Task { await backend.updatePrefs(prefs) }
            showThemeSheet = false
        } label: {
            FluxSettingsTile(icon: icon, title: title, iconColor: FluxColors.violet, iconBackground: FluxColors.violetSoft) {
                if theme.mode == mode {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21))
                        .foregroundStyle(FluxColors.online)
                }
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    private var languageSheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            Text(l10n.languageTitle)
                .font(.system(size: 18, weight: .heavy))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 18, leading: 20, bottom: 10, trailing: 20))
            languageOption("Русский", code: "ru")
            languageOption("English", code: "en")
            Spacer(minLength: 12)
        }
        .background(FluxColors.background.ignoresSafeArea())
        .presentationDetents([.height(240)])
    }

    private func languageOption(_ title: String, code: String) -> some View {
        Button {
            Haptics.selection()
            l10n.setLanguage(code)
            var prefs = backend.prefs
            prefs.language = code
            Task { await backend.updatePrefs(prefs) }
            showLanguageSheet = false
        } label: {
            FluxSettingsTile(icon: "character.bubble", title: title) {
                if l10n.language == code {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21))
                        .foregroundStyle(FluxColors.online)
                }
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13))
            .foregroundStyle(FluxColors.textTertiary)
    }
}

extension View {
    /// Liquid Glass (0.3): translucent material fill, 1pt hairline border
    /// and a subtle shadow. Reused by settings cards and other surfaces.
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func settingsCard() -> some View {
        glassCard(cornerRadius: 24)
            .padding(.horizontal, 8)
    }
}

/// Liquid-glass card background: `Material.ultraThinMaterial` fill with a
/// soft border (white ~0.12 in dark, separator in light) and mild shadow.
struct GlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : FluxColors.separator
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Material.ultraThinMaterial)
                    .shadow(color: Color(hex: 0x1A2340).opacity(0.05), radius: 16, y: 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
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
