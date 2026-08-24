import SwiftUI

/// The redesigned full profile (own AND other users):
/// Banner → Avatar → Message/Gift/••• → Name → Username → дни в Flux →
/// streak → Badges → информация → Stories / Gifts / Подписи.
struct UserProfileView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n
    @Environment(\.dismiss) private var dismiss

    /// `nil` = the own profile. An empty or unknown id is NOT treated as own —
    /// the view shows the «Пользователь не найден» placeholder instead
    /// (fixes the bug where the own profile opened instead of the peer's).
    let userId: String?

    @State private var showGiftCatalog = false
    @State private var showMoreMenu = false
    @State private var showSignatureComposer = false
    @State private var showSignatureSettings = false
    @State private var showStoriesViewer = false
    @State private var storiesIndex = 0
    @State private var showTheirQR = false
    @State private var toast: Toast?
    @State private var sentGift: FluxGift?
    @State private var pushChatId: String?
    @State private var moderationTarget: FluxUser?
    @State private var badgeDetail: FluxBadge?
    /// On-demand peer resolution state (mirrors the Dart `_resolveUser`).
    @State private var resolvingUser = false
    @State private var userResolveFailed = false

    private var isOwnProfile: Bool {
        guard let userId, !userId.isEmpty else { return userId == nil }
        return userId == backend.me?.id
    }

    private var user: FluxUser? {
        if isOwnProfile { return backend.me }
        guard let userId, !userId.isEmpty else { return nil }
        return backend.userById(userId)
    }

    private var profile: UserProfile {
        if isOwnProfile { return backend.myProfile }
        if let userId, !userId.isEmpty {
            return backend.profileOf(userId) ?? UserProfile()
        }
        return UserProfile()
    }

    var body: some View {
        Group {
            if let user {
                content(user: user, profile: profile)
            } else if resolvingUser {
                // The contact is not cached locally yet — load the real user
                // data from the shared backend instead of dead-ending.
                ProgressView()
                    .tint(FluxColors.blue)
            } else {
                Text("Пользователь не найден")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FluxColors.textSecondary)
            }
        }
        .background(FluxColors.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .fluxToast($toast)
        .onAppear { resolveUserIfNeeded() }
    }

    /// Fetches the real user document from the shared backend when the
    /// contact is not cached locally yet (e.g. the profile was opened from a
    /// chat whose peer has not been pulled into the directory). Mirrors the
    /// Dart `_resolveUser`.
    private func resolveUserIfNeeded() {
        guard !isOwnProfile, let userId, !userId.isEmpty else { return }
        guard user == nil, !resolvingUser, !userResolveFailed else { return }
        resolvingUser = true
        Task {
            let fetched = await backend.ensureUser(userId)
            resolvingUser = false
            if fetched == nil {
                userResolveFailed = true
            }
        }
    }

    // MARK: Content

    private func content(user: FluxUser, profile: UserProfile) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                bannerSection(user: user)
                headerSection(user: user, profile: profile)
                if !profile.displayBadges.isEmpty && profile.visibility.showBadges {
                    BadgeRowView(badges: profile.displayBadges) { badge in
                        badgeDetail = badge
                    }
                    .padding(.top, 14)
                }
                xpCard(profile: profile)
                    .padding(.top, 14)
                if isOwnProfile {
                    coinsCard
                        .padding(.top, 10)
                }
                infoSection(user: user, profile: profile)
                StoriesGiftsSignaturesTabs(
                    profile: profile,
                    isOwnProfile: isOwnProfile,
                    onOpenStory: { index in
                        storiesIndex = index
                        showStoriesViewer = true
                    },
                    onOpenSignatureSettings: { showSignatureSettings = true },
                    onLeaveSignature: { showSignatureComposer = true }
                )
                .padding(.top, 20)
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) {
            topButtons(user: user)
        }
        .sheet(isPresented: $showGiftCatalog) {
            GiftCatalogSheet(recipient: user) { gift in
                sentGift = gift
            }
            .environmentObject(backend)
        }
        .sheet(isPresented: $showSignatureComposer) {
            SignatureComposerSheet(recipient: user) { result in
                toast = Toast(text: result)
            }
        }
        .sheet(isPresented: $showSignatureSettings) {
            SignatureSettingsSheet()
        }
        .sheet(isPresented: $showTheirQR) {
            VStack(spacing: 18) {
                Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
                Text("QR-код \(user.name)")
                    .font(.system(size: 18, weight: .heavy))
                QRCodeView(fluxId: user.fluxId, size: 200)
                Spacer()
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $moderationTarget) { target in
            ModerationSheet(user: target)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $badgeDetail) { badge in
            BadgeDetailSheet(badge: badge)
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showStoriesViewer) {
            StoriesViewer(
                stories: profile.stories.filter { !$0.isExpired },
                startIndex: storiesIndex
            )
        }
        .fullScreenCover(item: $sentGift) { gift in
            GiftSentOverlay(gift: gift, recipientName: user.name)
        }
    }

    // MARK: Banner + avatar

    private func bannerSection(user: FluxUser) -> some View {
        ZStack(alignment: .bottomLeading) {
            FluxBannerView(user: user, bannerPath: profile.bannerPath, height: 200)
            FluxAvatarView(user: user, size: 90)
                .overlay(Circle().stroke(FluxColors.background, lineWidth: 4))
                .padding(.leading, 20)
                .padding(.bottom, -45)
        }
        .padding(.bottom, 45)
    }

    private func topButtons(user: FluxUser) -> some View {
        HStack {
            Button {
                Haptics.light()
                dismiss()
            } label: {
                circleButton(systemImage: "chevron.left")
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.9))
            Spacer()
            if isOwnProfile {
                NavigationLink(value: Route.myQR) {
                    circleButton(systemImage: "qrcode")
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.9))
                NavigationLink(value: Route.editProfile) {
                    circleButton(systemImage: "pencil")
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.9))
            }
            Button {
                Haptics.light()
                showMoreMenu = true
            } label: {
                circleButton(systemImage: "ellipsis")
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.9))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .sheet(isPresented: $showMoreMenu) {
            moreMenuSheet(user: user)
                .presentationDetents([.height(moreMenuHeight)])
        }
    }

    private var moreMenuHeight: CGFloat {
        !isOwnProfile && backend.me?.isAdmin == true ? 340 : 280
    }

    private func circleButton(systemImage: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.35))
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
    }

    private func moreMenuSheet(user: FluxUser) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            ShareLink(item: QRCodeGenerator.deepLink(fluxId: user.fluxId)) {
                FluxSettingsTile(icon: "square.and.arrow.up", title: "Поделиться профилем")
                    .padding(.horizontal, 8)
            }
            if !isOwnProfile {
                if backend.me?.isAdmin == true {
                    Button {
                        moderationTarget = user
                        showMoreMenu = false
                    } label: {
                        FluxSettingsTile(
                            icon: "gavel",
                            title: "Модерация (Mute / Freeze)",
                            iconColor: FluxColors.warning,
                            iconBackground: FluxColors.warning.opacity(0.12)
                        )
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    showTheirQR = true
                    showMoreMenu = false
                } label: {
                    FluxSettingsTile(icon: "qrcode", title: "QR-код профиля", iconColor: FluxColors.violet, iconBackground: FluxColors.violetSoft)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                Button {
                    toggleBlock(user: user)
                } label: {
                    FluxSettingsTile(
                        icon: "hand.raised.slash",
                        title: isUserBlocked(user) ? "Разблокировать" : "Заблокировать",
                        iconColor: FluxColors.danger,
                        iconBackground: FluxColors.danger.opacity(0.1)
                    )
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                Button {
                    submitReport(user: user)
                } label: {
                    FluxSettingsTile(
                        icon: "flag",
                        title: "Пожаловаться",
                        iconColor: FluxColors.danger,
                        iconBackground: FluxColors.danger.opacity(0.1)
                    )
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 12)
        }
        .background(FluxColors.background.ignoresSafeArea())
    }

    private func isUserBlocked(_ user: FluxUser) -> Bool {
        backend.profileVisibility.blockedSignatureUserIds.contains(user.id)
    }

    private func toggleBlock(user: FluxUser) {
        var visibility = backend.profileVisibility
        if let index = visibility.blockedSignatureUserIds.firstIndex(of: user.id) {
            visibility.blockedSignatureUserIds.remove(at: index)
            toast = Toast(text: "Пользователь разблокирован")
        } else {
            visibility.blockedSignatureUserIds.append(user.id)
            toast = Toast(text: "Пользователь заблокирован")
        }
        Task { await backend.updateVisibility(visibility) }
        showMoreMenu = false
    }

    private func submitReport(user: FluxUser) {
        showMoreMenu = false
        Task {
            await backend.submitReport(against: user)
            toast = Toast(text: "Жалоба отправлена в Службу безопасности")
        }
    }

    // MARK: Header

    private func headerSection(user: FluxUser, profile: UserProfile) -> some View {
        VStack(spacing: 0) {
            actionRow(user: user)

            HStack(spacing: 10) {
                Text(user.name)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(FluxColors.textPrimary)
                    .lineLimit(1)
                LevelBadgeView(level: profile.level, size: 36)
                if user.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(FluxColors.blue)
                }
                if user.isPremium {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(FluxColors.gold)
                }
            }
            .padding(.top, 4)

            subRow(user: user)
                .padding(.top, 6)

            if !user.status.isEmpty {
                Text(user.status)
                    .font(.system(size: 14))
                    .foregroundStyle(FluxColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
    }

    private func actionRow(user: FluxUser) -> some View {
        HStack(spacing: 10) {
            Spacer()
            if !isOwnProfile {
                // Message — opens (or creates) the chat, then pushes it.
                Button {
                    Haptics.light()
                    Task {
                        if backend.chatWithPeer(user.id) == nil {
                            if backend.me?.isFrozen == true {
                                toast = Toast(text: "❄️ Аккаунт заморожен — изменения недоступны.")
                                return
                            }
                            if backend.me?.isMuted == true {
                                toast = Toast(text: "Вы не можете начать новые диалоги.")
                                return
                            }
                        }
                        let chat = await backend.openChatWithUser(user)
                        pushChatId = chat.id
                    }
                } label: {
                    actionCircle(icon: "bubble.left.and.bubble.right.fill", gradient: FluxColors.gradient)
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.9))
                // Gift
                Button {
                    Haptics.light()
                    showGiftCatalog = true
                } label: {
                    actionCircle(
                        icon: "gift.fill",
                        gradient: LinearGradient(colors: [Color(hex: 0xFFB020), Color(hex: 0xFF6B00)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.9))
            }
        }
        .padding(.bottom, 10)
        .navigationDestination(isPresented: Binding(
            get: { pushChatId != nil },
            set: { if !$0 { pushChatId = nil } }
        )) {
            if let chatId = pushChatId {
                ChatView(chatId: chatId)
            }
        }
    }

    private func actionCircle(icon: String, gradient: LinearGradient) -> some View {
        ZStack {
            Circle().fill(gradient)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
    }

    private func subRow(user: FluxUser) -> some View {
        VStack(spacing: 6) {
            if let username = user.username {
                HStack(spacing: 6) {
                    Text("@\(username)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FluxColors.blue)
                    if let days = daysInFluxString(registeredAtMs: effectiveRegistrationDate(user: user)) {
                        Text("·")
                            .foregroundStyle(FluxColors.textTertiary)
                        Text(days)
                            .font(.system(size: 14))
                            .foregroundStyle(FluxColors.textSecondary)
                    }
                }
            } else if let days = daysInFluxString(registeredAtMs: effectiveRegistrationDate(user: user)) {
                Text(days)
                    .font(.system(size: 14))
                    .foregroundStyle(FluxColors.textSecondary)
            }
            if profile.dailyStreak.currentStreak > 0 {
                Text("🔥 Серия: \(profile.dailyStreak.currentStreak) \(pluralRu(profile.dailyStreak.currentStreak, "день", "дня", "дней"))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FluxColors.warning)
            }
        }
    }

    /// Prefers the explicit registeredAtMs; falls back to the first badge
    /// earn date for accounts restored from remote snapshots.
    private func effectiveRegistrationDate(user: FluxUser) -> Int? {
        if let registeredAtMs = user.registeredAtMs, registeredAtMs > 0 {
            return registeredAtMs
        }
        return profile.badges.compactMap { $0.earnedAtMs }.min()
    }

    // MARK: XP / coins cards

    private func xpCard(profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LevelBadgeView(level: profile.level, size: 28)
                Text("Level \(profile.level)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FluxColors.textPrimary)
                Spacer()
                if let next = profile.nextLevelXp {
                    Text("\(profile.activityPoints) / \(next) XP")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FluxColors.textSecondary)
                } else {
                    Text("\(profile.activityPoints) XP")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FluxColors.textSecondary)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(FluxColors.surfaceGray)
                    Capsule()
                        .fill(LinearGradient(colors: profile.tier.gradient, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geometry.size.width * profile.xpProgress))
                }
            }
            .frame(height: 8)
            Text("\(Int(profile.xpProgress * 100))%")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FluxColors.textTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FluxColors.cardSecondary)
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
        )
        .padding(.horizontal, 16)
    }

    private var coinsCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FluxColors.warning.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(
                    Text("🪙")
                        .font(.system(size: 20))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Flux Coins")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FluxColors.textSecondary)
                Text("\(backend.fluxCoins) монет")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(FluxColors.warning)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FluxColors.cardSecondary)
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
        )
        .padding(.horizontal, 16)
    }

    // MARK: Info

    @ViewBuilder
    private func infoSection(user: FluxUser, profile: UserProfile) -> some View {
        let rows = infoRows(user: user, profile: profile)
        if !rows.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        Image(systemName: row.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(row.color)
                        Text(row.text)
                            .font(.system(size: 13, weight: row.bold ? .semibold : .regular))
                            .foregroundStyle(row.color)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
        }
        Divider()
            .overlay(FluxColors.separator)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
    }

    private struct InfoRow {
        let icon: String
        let text: String
        let color: Color
        var bold = false
    }

    private func infoRows(user: FluxUser, profile: UserProfile) -> [InfoRow] {
        var rows: [InfoRow] = []
        if let location = profile.location, !location.isEmpty {
            rows.append(InfoRow(icon: "mappin.and.ellipse", text: location, color: FluxColors.danger))
        }
        if let website = profile.website, !website.isEmpty {
            rows.append(InfoRow(icon: "link", text: website, color: FluxColors.blue, bold: true))
        }
        if let registeredAtMs = effectiveRegistrationDate(user: user) {
            let comps = Calendar.current.dateComponents([.month, .year], from: Date(timeIntervalSince1970: TimeInterval(registeredAtMs) / 1000))
            let text = "На Flux с \(monthsRuShort[(comps.month ?? 1) - 1]) \(comps.year ?? 2024)"
            rows.append(InfoRow(icon: "calendar", text: text, color: FluxColors.violet))
        }
        if profile.visibility.showBirthday,
           let birthday = birthdayDisplayString(profile.birthday, showAge: profile.visibility.showAge) {
            rows.append(InfoRow(icon: "gift", text: birthday.replacingOccurrences(of: "🎂 ", with: ""), color: FluxColors.warning))
        }
        if profile.visibility.showAdditionalUsernames {
            for entry in profile.additionalUsernames {
                rows.append(InfoRow(icon: "at", text: "@\(entry.username) · дополнительный", color: FluxColors.blue))
            }
        }
        return rows
    }
}
