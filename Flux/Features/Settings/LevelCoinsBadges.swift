import SwiftUI

/// Настройки → Уровень и активность: the detailed Level/XP breakdown
/// (kept out of the profile to avoid overloading it).
struct LevelActivityView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    private var profile: UserProfile { backend.myProfile }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Big level card
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [profile.tier.gradient[0].opacity(0.4), .clear],
                                    center: .center, startRadius: 10, endRadius: 100)
                            )
                            .frame(width: 150, height: 150)
                        Circle()
                            .fill(LinearGradient(colors: profile.tier.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 100, height: 100)
                            .shadow(color: profile.tier.gradient[0].opacity(0.5), radius: 24, y: 4)
                            .overlay(
                                VStack(spacing: 0) {
                                    Text("\(profile.level)")
                                        .font(.system(size: 34, weight: .heavy))
                                        .foregroundStyle(.white)
                                    Text("LEVEL")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(1.5)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            )
                    }
                    Text("Level \(profile.level)")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(FluxColors.textPrimary)
                    Text("Всего XP: \(profile.activityPoints)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FluxColors.textSecondary)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(FluxColors.surfaceGray)
                            Capsule()
                                .fill(LinearGradient(colors: profile.tier.gradient, startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, geometry.size.width * profile.xpProgress))
                        }
                    }
                    .frame(height: 8)

                    if let next = profile.nextLevelXp {
                        Text("До уровня \(profile.level + 1): \(next - profile.activityPoints) XP")
                            .font(.system(size: 13))
                            .foregroundStyle(FluxColors.textTertiary)
                    } else {
                        Text("Максимальный уровень достигнут 🎉")
                            .font(.system(size: 13))
                            .foregroundStyle(FluxColors.textTertiary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(FluxColors.surface)
                        .shadow(color: Color(hex: 0x1A2340).opacity(0.04), radius: 16, y: 6)
                )
                .padding(EdgeInsets(top: 16, leading: 8, bottom: 8, trailing: 8))

                // Streak card
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(FluxColors.warning.opacity(0.12))
                            .frame(width: 46, height: 46)
                        Text("🔥")
                            .font(.system(size: 22))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Серия: \(profile.dailyStreak.currentStreak) \(pluralRu(profile.dailyStreak.currentStreak, "день", "дня", "дней"))")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(FluxColors.textPrimary)
                        Text("Лучшая серия: \(profile.dailyStreak.longestStreak) \(pluralRu(profile.dailyStreak.longestStreak, "день", "дня", "дней")) · заходите каждый день за +25 🪙")
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
                .padding(EdgeInsets(top: 6, leading: 8, bottom: 8, trailing: 8))

                // How to earn XP
                FluxSectionTitle(text: "Как получить XP")
                VStack(spacing: 0) {
                    FluxSettingsTile(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Отправить сообщение",
                        subtitle: "+1 XP за каждое",
                        showDivider: true
                    )
                    .padding(.horizontal, 8)
                    FluxSettingsTile(
                        icon: "gift.fill",
                        title: "Получить подарок",
                        subtitle: "+10 XP за подарок",
                        iconColor: FluxColors.warning,
                        iconBackground: FluxColors.warning.opacity(0.13)
                    )
                    .padding(.horizontal, 8)
                }
                .settingsCard()

                // Badge progress
                FluxSectionTitle(text: "Достижения")
                VStack(spacing: 0) {
                    ForEach(Array(BadgeCatalog.xpMilestones.enumerated()), id: \.element.id) { index, badge in
                        let earned = profile.badges.contains { $0.id == badge.id }
                        FluxSettingsTile(
                            icon: earned ? "checkmark.circle.fill" : "circle.dashed",
                            title: "\(badge.emoji) \(badge.name)",
                            subtitle: earned ? "Получен" : "Набрать \(badge.xpPoints) XP",
                            iconColor: earned ? FluxColors.online : FluxColors.textTertiary,
                            iconBackground: earned ? FluxColors.online.opacity(0.12) : FluxColors.surfaceGray,
                            showDivider: index < BadgeCatalog.xpMilestones.count - 1
                        )
                        .padding(.horizontal, 8)
                    }
                }
                .settingsCard()
                .padding(.bottom, 32)
            }
        }
        .background(FluxColors.background.ignoresSafeArea())
        .navigationTitle("Уровень и активность")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Настройки → Flux Coins: balance, history of purchases and spending.
struct FluxCoinsView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("🪙")
                        .font(.system(size: 44))
                    Text("\(backend.fluxCoins)")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(FluxColors.warning)
                    Text("монет")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FluxColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [FluxColors.warning.opacity(0.12), FluxColors.warning.opacity(0.04)],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(FluxColors.warning.opacity(0.25), lineWidth: 1))
                )
                .padding(EdgeInsets(top: 16, leading: 8, bottom: 8, trailing: 8))

                FluxSectionTitle(text: "Куда тратятся")
                VStack(spacing: 0) {
                    FluxSettingsTile(icon: "gift.fill", title: "Подарки", subtitle: "10 – 1000 монет", iconColor: FluxColors.warning, iconBackground: FluxColors.warning.opacity(0.13), showDivider: true)
                        .padding(.horizontal, 8)
                    FluxSettingsTile(icon: "rosette", title: "Бейджи из магазина", subtitle: "200 – 5000 монет", showDivider: true)
                        .padding(.horizontal, 8)
                    FluxSettingsTile(icon: "at", title: "Marketplace username", subtitle: "цена продавца", iconColor: FluxColors.online, iconBackground: FluxColors.online.opacity(0.12))
                        .padding(.horizontal, 8)
                }
                .settingsCard()

                FluxSectionTitle(text: "История операций")
                if backend.coinTransactions.isEmpty {
                    VStack(spacing: 8) {
                        Text("🪙")
                            .font(.system(size: 30))
                        Text("Операций пока нет")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(FluxColors.textPrimary)
                        Text("Ежедневный вход приносит +25 монет")
                            .font(.system(size: 13))
                            .foregroundStyle(FluxColors.textTertiary)
                    }
                    .padding(.top, 30)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(backend.coinTransactions.enumerated()), id: \.element.id) { index, tx in
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(tx.amount > 0 ? FluxColors.online.opacity(0.12) : FluxColors.danger.opacity(0.1))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: txIcon(tx.type))
                                        .font(.system(size: 16))
                                        .foregroundStyle(tx.amount > 0 ? FluxColors.online : FluxColors.danger)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tx.description.isEmpty ? tx.type.label : tx.description)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(FluxColors.textPrimary)
                                        .lineLimit(1)
                                    Text("\(tx.type.label) · \(formatChatTime(tx.timestampMs))")
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(FluxColors.textTertiary)
                                }
                                Spacer()
                                Text(tx.amount > 0 ? "+\(tx.amount)" : "\(tx.amount)")
                                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                                    .foregroundStyle(tx.amount > 0 ? FluxColors.online : FluxColors.danger)
                            }
                            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                            if index < backend.coinTransactions.count - 1 {
                                Divider().overlay(FluxColors.separator).padding(.leading, 64)
                            }
                        }
                    }
                    .settingsCard()
                    .padding(.bottom, 32)
                }
            }
        }
        .background(FluxColors.background.ignoresSafeArea())
        .navigationTitle("Flux Coins")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func txIcon(_ type: CoinTransactionType) -> String {
        switch type {
        case .bonus: return "plus.circle.fill"
        case .giftSent: return "gift.fill"
        case .giftReceived: return "gift"
        case .badgePurchase: return "rosette"
        case .usernamePurchase: return "at"
        case .usernameSale: return "at"
        case .dailyReward: return "flame.fill"
        case .levelUp: return "arrow.up.circle.fill"
        case .coinsTransferSent: return "arrow.up"
        case .coinsTransferReceived: return "arrow.down"
        case .checkCreated: return "receipt"
        case .checkRedeemed: return "receipt"
        case .checkRefund: return "receipt"
        case .p2pEscrow: return "lock.fill"
        case .p2pReleased: return "arrow.left.arrow.right"
        case .p2pRefund: return "lock.open.fill"
        }
    }
}

/// Настройки → Магазин бейджей: purchasable badges for Flux Coins.
struct BadgeShopView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    @State private var confirmBadge: FluxBadge?
    @State private var toast: Toast?
    @State private var badgeDetail: FluxBadge?

    private var ownedIds: Set<String> {
        Set(backend.myProfile.badges.map { $0.id })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("🪙")
                        .font(.system(size: 20))
                    Text("Ваш баланс: \(backend.fluxCoins) монет")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FluxColors.warning)
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(FluxColors.warning.opacity(0.1))
                )
                .padding(EdgeInsets(top: 16, leading: 12, bottom: 12, trailing: 12))

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(BadgeShopCatalog.shopBadges) { badge in
                        let owned = ownedIds.contains(badge.id)
                        Button {
                            Haptics.light()
                            if owned {
                                badgeDetail = badge
                            } else {
                                confirmBadge = badge
                            }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [badge.rarity.color.opacity(0.2), badge.rarity.color.opacity(0.06)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing)
                                        )
                                        .frame(width: 56, height: 56)
                                        .overlay(Circle().strokeBorder(badge.rarity.color.opacity(0.4), lineWidth: 1.5))
                                    Text(badge.emoji)
                                        .font(.system(size: 26))
                                }
                                Text(badge.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(FluxColors.textPrimary)
                                Text(badge.description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(FluxColors.textTertiary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(height: 28)
                                if owned {
                                    Text("Получен ✓")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(FluxColors.online)
                                } else {
                                    Text("\(badge.cost) 🪙")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(badge.rarity.color)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(FluxColors.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(badge.rarity.color.opacity(0.25), lineWidth: 1))
                            )
                        }
                        .buttonStyle(ScaleButtonStyle(scale: 0.97))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 32)
            }
        }
        .background(FluxColors.background.ignoresSafeArea())
        .navigationTitle("Магазин бейджей")
        .navigationBarTitleDisplayMode(.inline)
        .fluxToast($toast)
        .sheet(item: $confirmBadge) { badge in
            purchaseSheet(badge)
                .presentationDetents([.height(320)])
        }
        .sheet(item: $badgeDetail) { badge in
            BadgeDetailSheet(badge: badge)
                .presentationDetents([.medium])
        }
    }

    private func purchaseSheet(_ badge: FluxBadge) -> some View {
        VStack(spacing: 14) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            Text(badge.emoji)
                .font(.system(size: 44))
            Text(badge.name)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(FluxColors.textPrimary)
            Text("Купить этот бейдж за \(badge.cost) монет?")
                .font(.system(size: 14))
                .foregroundStyle(FluxColors.textSecondary)
            Text("Баланс после покупки: \(max(0, backend.fluxCoins - badge.cost)) 🪙")
                .font(.system(size: 13))
                .foregroundStyle(FluxColors.textTertiary)
            FluxButton(title: "Купить за \(badge.cost) 🪙", enabled: backend.fluxCoins >= badge.cost) {
                Task {
                    do {
                        try await backend.purchaseBadge(badge.id)
                        Haptics.success()
                        confirmBadge = nil
                        toast = Toast(text: "Бейдж «\(badge.name)» получен!")
                    } catch {
                        toast = Toast(text: error.localizedDescription, isError: true)
                    }
                }
            }
            .padding(.horizontal, 20)
            if backend.fluxCoins < badge.cost {
                Text("Недостаточно монет — заходите каждый день за наградой")
                    .font(.system(size: 12))
                    .foregroundStyle(FluxColors.danger)
            }
            Spacer(minLength: 12)
        }
        .background(FluxColors.background.ignoresSafeArea())
    }
}
