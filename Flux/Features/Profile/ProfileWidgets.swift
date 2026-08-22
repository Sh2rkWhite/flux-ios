import SwiftUI

// MARK: - Badge row

/// Compact, bright, tappable badge chips (the new badge system).
struct BadgeRowView: View {
    let badges: [FluxBadge]
    var onTap: ((FluxBadge) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(badges) { badge in
                    Button {
                        Haptics.light()
                        onTap?(badge)
                    } label: {
                        HStack(spacing: 5) {
                            Text(badge.emoji)
                                .font(.system(size: 14))
                            Text(badge.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(badge.rarity.color)
                                .lineLimit(1)
                        }
                        .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                        .background(
                            Capsule()
                                .fill(FluxColors.cardSecondary)
                                .overlay(Capsule().strokeBorder(badge.rarity.color.opacity(0.4), lineWidth: 1.5))
                                .shadow(color: badge.rarity.color.opacity(0.15), radius: 8, y: 2)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Badge detail card: name, description, condition, rarity, XP points.
struct BadgeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let badge: FluxBadge

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [badge.rarity.color.opacity(0.2), badge.rarity.color.opacity(0.05)],
                            center: .center, startRadius: 4, endRadius: 70)
                    )
                    .frame(width: 80, height: 80)
                    .overlay(Circle().strokeBorder(badge.rarity.color.opacity(0.4), lineWidth: 2))
                Text(badge.emoji)
                    .font(.system(size: 36))
            }
            .padding(.top, 24)

            Text(badge.name)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(FluxColors.textPrimary)
                .padding(.top, 16)

            Text(badge.description)
                .font(.system(size: 15))
                .foregroundStyle(FluxColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            HStack(spacing: 8) {
                Text(badge.rarity.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(badge.rarity.color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(badge.rarity.color.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(badge.rarity.color.opacity(0.3), lineWidth: 1))
                Text(badge.badgeType.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FluxColors.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(FluxColors.surfaceGray))
            }
            .padding(.top, 14)

            if badge.xpPoints > 0 {
                Text("Требуется: \(badge.xpPoints) XP")
                    .font(.system(size: 13))
                    .foregroundStyle(FluxColors.textTertiary)
                    .padding(.top, 8)
            }
            if badge.isPurchasable {
                Text("Стоимость: \(badge.cost) 🪙")
                    .font(.system(size: 13))
                    .foregroundStyle(FluxColors.warning)
                    .padding(.top, 4)
            }
            if let earnedAtMs = badge.earnedAtMs {
                Text("Получен: \(formatDayDivider(earnedAtMs))")
                    .font(.system(size: 13))
                    .foregroundStyle(FluxColors.textTertiary)
                    .padding(.top, 4)
            }

            Button {
                Haptics.light()
                dismiss()
            } label: {
                Text("Закрыть")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FluxColors.blue)
                    .padding(.top, 18)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 24)
        .background(FluxColors.background.ignoresSafeArea())
    }
}

// MARK: - Stories / Gifts / Подписи tabs

/// The bottom profile section with three tabs and a thin divider.
struct StoriesGiftsSignaturesTabs: View {
    @EnvironmentObject var backend: LocalBackend

    let profile: UserProfile
    let isOwnProfile: Bool
    let onOpenStory: (Int) -> Void
    let onOpenSignatureSettings: () -> Void
    let onLeaveSignature: () -> Void

    @State private var tab = 0
    @State private var badgeDetail: FluxBadge?
    @State private var giftDetail: FluxGift?

    private var liveStories: [FluxStory] {
        profile.stories.filter { !$0.isExpired }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(FluxColors.separator)

            HStack(spacing: 4) {
                tabButton(title: "Stories", count: profile.visibility.showStories ? liveStories.count : 0, index: 0)
                tabButton(title: "Gifts", count: profile.visibility.showGifts ? profile.gifts.count : 0, index: 1)
                tabButton(title: "Подписи", count: profile.visibility.showSignatures ? profile.approvedSignatures.count : 0, index: 2)
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FluxColors.surfaceGray)
            )
            .padding(.horizontal, 16)

            Group {
                switch tab {
                case 0: storiesTab
                case 1: giftsTab
                default: signaturesTab
                }
            }
            .frame(height: 260)
        }
        .sheet(item: $badgeDetail) { badge in
            BadgeDetailSheet(badge: badge)
                .presentationDetents([.medium])
        }
        .sheet(item: $giftDetail) { gift in
            GiftDetailSheet(gift: gift)
                .presentationDetents([.medium])
        }
    }

    private func tabButton(title: String, count: Int, index: Int) -> some View {
        Button {
            Haptics.selection()
            withAnimation(FluxMotion.springAnimation) { tab = index }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: tab == index ? .bold : .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.25)))
                }
            }
            .foregroundStyle(tab == index ? .white : FluxColors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tab == index ? AnyShapeStyle(FluxColors.gradient) : AnyShapeStyle(Color.clear))
                    .shadow(color: FluxColors.blue.opacity(tab == index ? 0.3 : 0), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Stories

    @ViewBuilder
    private var storiesTab: some View {
        if !profile.visibility.showStories {
            tabEmptyState(emoji: "🙈", title: "Истории скрыты")
        } else if liveStories.isEmpty {
            tabEmptyState(emoji: "📖", title: "Нет активных историй", hint: "Истории появятся здесь")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(liveStories.enumerated()), id: \.element.id) { index, story in
                        Button {
                            Haptics.light()
                            onOpenStory(index)
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                storyThumb(story)
                                Text("24h")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.black.opacity(0.4))
                                    )
                                    .padding(6)
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func storyThumb(_ story: FluxStory) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let image = UIImage(contentsOfFile: story.mediaPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(FluxColors.gradient)
            }
            if let caption = story.caption {
                Text(caption)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
        }
        .frame(width: 120, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: FluxColors.blue.opacity(0.2), radius: 8, y: 3)
    }

    // MARK: Gifts

    @ViewBuilder
    private var giftsTab: some View {
        if !profile.visibility.showGifts {
            tabEmptyState(emoji: "🙈", title: "Подарки скрыты")
        } else if profile.gifts.isEmpty {
            tabEmptyState(emoji: "🎁", title: "Подарков пока нет", hint: "Подарки появятся здесь")
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(profile.gifts) { gift in
                        Button {
                            Haptics.light()
                            giftDetail = gift
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(LinearGradient(colors: gift.rarity.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.18))
                                    .frame(width: 48, height: 48)
                                    .overlay(Text(gift.emoji).font(.system(size: 24)))
                                Text(gift.name)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(FluxColors.textPrimary)
                                    .lineLimit(1)
                                Text(gift.rarity.label)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(gift.rarity.color)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(gift.rarity.color.opacity(0.12)))
                                Text("от \(gift.fromUserName)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(FluxColors.textTertiary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(0.85, contentMode: .fit)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(FluxColors.cardSecondary)
                                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(gift.rarity.color.opacity(0.25), lineWidth: 1))
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Подписи (signatures guestbook)

    @ViewBuilder
    private var signaturesTab: some View {
        VStack(spacing: 0) {
            if isOwnProfile {
                HStack {
                    Text("Мои подписи")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FluxColors.textSecondary)
                    Spacer()
                    Button {
                        Haptics.light()
                        onOpenSignatureSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundStyle(FluxColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                pendingSection
                approvedSignatures
            } else {
                if !profile.visibility.showSignatures {
                    tabEmptyState(emoji: "🙈", title: "Подписи скрыты")
                } else if !profile.visibility.allowSignatures {
                    tabEmptyState(emoji: "🚫", title: "Владелец запретил подписи")
                } else {
                    approvedSignatures
                    leaveSignatureButton
                }
            }
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        let pending = profile.pendingSignatures
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("На рассмотрении · \(pending.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FluxColors.warning)
                    .padding(.horizontal, 16)
                ForEach(pending) { signature in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(signature.authorName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(FluxColors.textPrimary)
                            Text(signature.text)
                                .font(.system(size: 13))
                                .foregroundStyle(FluxColors.textSecondary)
                        }
                        Spacer()
                        Button {
                            Haptics.medium()
                            Task { await backend.updateSignatureStatus(signature.id, .approved) }
                        } label: {
                            Text("Принять")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(FluxColors.online))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        Button {
                            Haptics.medium()
                            Task { await backend.updateSignatureStatus(signature.id, .rejected) }
                        } label: {
                            Text("Отклонить")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(FluxColors.danger)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(FluxColors.danger.opacity(0.12)))
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(FluxColors.cardSecondary)
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var approvedSignatures: some View {
        let approved = profile.approvedSignatures
        ScrollView {
            VStack(spacing: 8) {
                if approved.isEmpty {
                    VStack(spacing: 8) {
                        Text("✍️")
                            .font(.system(size: 30))
                        Text("Подписей пока нет")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(FluxColors.textPrimary)
                        if !isOwnProfile {
                            Text("Оставьте первый след в гостевой книге")
                                .font(.system(size: 13))
                                .foregroundStyle(FluxColors.textTertiary)
                        }
                    }
                    .padding(.top, 30)
                } else {
                    ForEach(approved) { signature in
                        HStack(alignment: .top, spacing: 10) {
                            ZStack {
                                Circle().fill(FluxColors.gradient)
                                Text(String(signature.authorName.prefix(1)).uppercased())
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(signature.authorName)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(FluxColors.textPrimary)
                                Text(signature.text)
                                    .font(.system(size: 13))
                                    .foregroundStyle(FluxColors.textSecondary)
                                Text(formatDayDivider(signature.createdAtMs))
                                    .font(.system(size: 11))
                                    .foregroundStyle(FluxColors.textTertiary)
                            }
                            Spacer()
                            if isOwnProfile {
                                Button {
                                    Haptics.medium()
                                    Task { await backend.deleteSignature(signature.id) }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundStyle(FluxColors.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(FluxColors.cardSecondary)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    private var leaveSignatureButton: some View {
        Button {
            Haptics.light()
            onLeaveSignature()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "pencil.line")
                Text("Оставить подпись")
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FluxColors.gradient)
                    .shadow(color: FluxColors.blue.opacity(0.3), radius: 10, y: 4)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
    }

    private func tabEmptyState(emoji: String, title: String, hint: String? = nil) -> some View {
        VStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 30))
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FluxColors.textPrimary)
            if let hint {
                Text(hint)
                    .font(.system(size: 13))
                    .foregroundStyle(FluxColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Gift detail sheet

struct GiftDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let gift: FluxGift

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: gift.rarity.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.2))
                    .frame(width: 88, height: 88)
                    .overlay(Circle().strokeBorder(gift.rarity.color.opacity(0.4), lineWidth: 2))
                    .shadow(color: gift.rarity.color.opacity(0.2), radius: 16, y: 4)
                Text(gift.emoji)
                    .font(.system(size: 40))
            }
            .padding(.top, 24)

            Text(gift.name)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(FluxColors.textPrimary)
                .padding(.top, 16)

            Text(gift.rarity.label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(gift.rarity.color)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(gift.rarity.color.opacity(0.12)))
                .padding(.top, 8)

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(FluxColors.gradient)
                    Text(String(gift.fromUserName.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("от \(gift.fromUserName)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FluxColors.textPrimary)
                    Text(formatDayDivider(gift.sentAtMs))
                        .font(.system(size: 12))
                        .foregroundStyle(FluxColors.textTertiary)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FluxColors.surfaceGray))
            .padding(.top, 16)

            if let message = gift.message, !message.isEmpty {
                Text("«\(message)»")
                    .font(.system(size: 14).italic())
                    .foregroundStyle(FluxColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(gift.rarity.color.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.top, 12)
            }

            Button {
                Haptics.light()
                dismiss()
            } label: {
                Text("Закрыть")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FluxColors.blue)
                    .padding(.top, 18)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 24)
        .background(FluxColors.background.ignoresSafeArea())
    }
}
