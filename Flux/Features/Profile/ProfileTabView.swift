import SwiftUI

/// The «Профиль» tab: profile header, premium, settings entries, admin,
/// language/theme, support, logout.
struct ProfileTabView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n
    @EnvironmentObject var theme: ThemeController
    @EnvironmentObject var lock: LockController

    @State private var showLogoutConfirm = false
    @State private var showLanguageSheet = false
    @State private var showThemeSheet = false
    @State private var toast: Toast?
    @State private var pushSupportChat = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    headerCard
                    premiumBanner
                    mainSettingsCard
                    if backend.isAdmin {
                        adminCard
                    }
                    languageThemeCard
                    supportCard
                    logoutButton
                }
                .padding(EdgeInsets(top: 16, leading: 8, bottom: 120, trailing: 8))
            }
            .background(FluxColors.background.ignoresSafeArea())
            .navigationDestination(for: Route.self) { route in
                RouteDestination(route: route)
            }
            .fluxToast($toast)
        }
    }

    // MARK: Header

    private var headerCard: some View {
        NavigationLink(value: Route.userProfile(userId: backend.me?.id ?? "")) {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    FluxAvatarView(user: backend.me, size: 96)
                        .overlay(Circle().stroke(FluxColors.surface, lineWidth: 4))
                    if backend.me?.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(FluxColors.blue))
                            .overlay(Circle().strokeBorder(FluxColors.background, lineWidth: 2.5))
                            .offset(x: -32, y: -4)
                    }
                    ZStack {
                        Circle().fill(FluxColors.gradient)
                        Image(systemName: "camera")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(FluxColors.background, lineWidth: 2.5))
                }
                Text(backend.me?.name ?? "")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(FluxColors.textPrimary)
                if let username = backend.me?.username {
                    Text("@\(username)")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(FluxColors.blue)
                }
                if backend.privacy.showOnline, backend.me?.isOnline == true {
                    Text(l10n.online)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FluxColors.online)
                } else if let status = backend.me?.status, !status.isEmpty {
                    Text(status)
                        .font(.system(size: 14))
                        .foregroundStyle(FluxColors.textSecondary)
                }
                HStack(spacing: 6) {
                    Image(systemName: "fingerprint")
                        .font(.system(size: 13))
                        .foregroundStyle(FluxColors.blue)
                    Text(backend.me?.fluxId ?? "")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(FluxColors.blue)
                }
                .padding(EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14))
                .background(
                    Capsule().fill(FluxColors.blueSoft)
                )
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(FluxColors.surface)
                    .shadow(color: Color(hex: 0x1A2340).opacity(0.04), radius: 16, y: 6)
            )
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.98))
        .padding(.horizontal, 4)
    }

    private var premiumBanner: some View {
        NavigationLink(value: Route.settings) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "crown.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flux Premium")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text(backend.me?.isPremium == true ? "Premium активен ✓" : l10n.premiumHint)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: backend.me?.isPremium == true ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(FluxColors.gradient)
            )
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.98))
        .simultaneousGesture(TapGesture().onEnded {
            Haptics.success()
            Task { await backend.updateMe(isPremium: !(backend.me?.isPremium ?? false)) }
        })
        .padding(EdgeInsets(top: 12, leading: 8, bottom: 6, trailing: 8))
    }

    // MARK: Settings cards

    private var mainSettingsCard: some View {
        VStack(spacing: 0) {
            NavigationLink(value: Route.userProfile(userId: backend.me?.id ?? "")) {
                FluxSettingsTile(icon: "person.fill", title: l10n.myProfile)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            Divider().overlay(FluxColors.separator).padding(.leading, 62)
            NavigationLink(value: Route.settings) {
                FluxSettingsTile(icon: "gearshape.fill", title: l10n.settings)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            Divider().overlay(FluxColors.separator).padding(.leading, 62)
            NavigationLink(value: Route.privacy) {
                FluxSettingsTile(icon: "lock.fill", title: l10n.privacy, iconColor: FluxColors.violet, iconBackground: FluxColors.violetSoft)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            Divider().overlay(FluxColors.separator).padding(.leading, 62)
            NavigationLink(value: Route.settings) {
                FluxSettingsTile(
                    icon: "bell.fill",
                    title: l10n.notifications,
                    iconColor: FluxColors.warning,
                    iconBackground: FluxColors.warning.opacity(0.13)
                ) {
                    Image(systemName: backend.prefs.notifications ? "checkmark.circle.fill" : "bell.slash")
                        .font(.system(size: 20))
                        .foregroundStyle(backend.prefs.notifications ? FluxColors.online : FluxColors.textTertiary)
                }
                .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FluxColors.surface)
        )
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
    }

    private var adminCard: some View {
        NavigationLink(value: Route.adminPanel) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.adminPanel)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text(l10n.adminPanelDesc)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
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

    private var languageThemeCard: some View {
        VStack(spacing: 0) {
            FluxSettingsTile(icon: "globe", title: l10n.languageTitle, iconColor: FluxColors.online, iconBackground: FluxColors.online.opacity(0.12)) {
                Text(l10n.isRu ? "Русский" : "English")
                    .font(.system(size: 14))
                    .foregroundStyle(FluxColors.textSecondary)
            } onTap: {
                showLanguageSheet = true
            }
            .padding(.horizontal, 8)
            Divider().overlay(FluxColors.separator).padding(.leading, 62)
            FluxSettingsTile(icon: "paintpalette.fill", title: l10n.theme, iconColor: FluxColors.violet, iconBackground: FluxColors.violetSoft) {
                Text(currentThemeLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(FluxColors.textSecondary)
            } onTap: {
                showThemeSheet = true
            }
            .padding(.horizontal, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FluxColors.surface)
        )
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
        .sheet(isPresented: $showLanguageSheet) { languageSheet }
        .sheet(isPresented: $showThemeSheet) { themeSheet }
    }

    private var currentThemeLabel: String {
        switch theme.mode {
        case .light: return l10n.themeLight
        case .dark: return l10n.themeDark
        case .system: return l10n.themeSystem
        }
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

    private var supportCard: some View {
        Button {
            Haptics.light()
            Task {
                _ = await backend.openChatWithUser(backend.ensureSupportUser())
                pushSupportChat = true
            }
        } label: {
            FluxSettingsTile(
                icon: "headphones",
                title: l10n.support,
                subtitle: l10n.online,
                trailing: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundStyle(FluxColors.textTertiary)
                })
                .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FluxColors.surface)
        )
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
        .navigationDestination(isPresented: $pushSupportChat) {
            ChatView(chatId: backend.chatWithPeer(FluxUser.supportId)?.id ?? "")
        }
    }

    // MARK: Logout

    private var logoutButton: some View {
        Button {
            Haptics.medium()
            showLogoutConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 18))
                Text(l10n.logout)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(FluxColors.danger)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(FluxColors.danger.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(FluxColors.danger.opacity(0.25), lineWidth: 1))
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
        .confirmationDialog(l10n.logoutConfirmTitle, isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button(l10n.logout, role: .destructive) {
                Task { await backend.logout() }
            }
            Button(l10n.cancel, role: .cancel) {}
        } message: {
            Text(l10n.logoutConfirmBody)
        }
    }
}
