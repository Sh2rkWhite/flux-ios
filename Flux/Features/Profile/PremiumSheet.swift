import SwiftUI

/// Flux Premium info sheet: benefits, subscription status and the support
/// contact. No fake purchases — the flag is managed by the Flux
/// administration, the sheet never flips it itself (mirrors the Android
/// `premium_sheet.dart`).
struct PremiumSheet: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n
    @Environment(\.dismiss) private var dismiss

    /// Invoked after the sheet is dismissed when the user taps
    /// «Написать в Flux Support».
    var onOpenSupportChat: () -> Void = {}

    private static let benefits: [(emoji: String, title: String, subtitle: String)] = [
        ("★", "Значок Premium", "Золотая звезда рядом с именем в чатах и профиле"),
        ("🏅", "Эксклюзивные бейджи", "Доступ к бейджам, недоступным без подписки"),
        ("🎨", "Оформление профиля", "Расширенные подписи и стиль профиля"),
        ("💙", "Приоритетная поддержка", "Быстрые ответы Flux Support"),
    ]

    var body: some View {
        let active = backend.me?.isPremium == true
        ScrollView {
            VStack(spacing: 0) {
                Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)

                ZStack {
                    Circle()
                        .fill(FluxColors.gradient)
                        .frame(width: 76, height: 76)
                        .shadow(color: Color(hex: 0x4E9BFF).opacity(0.35), radius: 12, y: 8)
                    Image(systemName: "medal.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                }
                .padding(.top, 22)

                Text("Flux Premium")
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(FluxColors.textPrimary)
                    .padding(.top, 16)

                Text(active ? "Premium активен ✓" : "Подписка не активна")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(active ? FluxColors.online : FluxColors.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(active ? FluxColors.online.opacity(0.12) : FluxColors.separator.opacity(0.4))
                    )
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    ForEach(Array(Self.benefits.enumerated()), id: \.offset) { _, benefit in
                        benefitRow(emoji: benefit.emoji, title: benefit.title, subtitle: benefit.subtitle)
                    }
                }
                .padding(.top, 24)

                Text(l10n.isRu
                     ? "Подписка Flux Premium выдаётся администрацией Flux. Оплата внутри приложения пока недоступна — напишите в Flux Support, чтобы узнать условия."
                     : "Flux Premium is granted by the Flux administration. In-app payment is not available yet — contact Flux Support for details.")
                    .font(.system(size: 12.5))
                    .lineSpacing(4)
                    .foregroundStyle(FluxColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(FluxColors.separator.opacity(0.25))
                    )
                    .padding(.top, 20)

                Button {
                    Haptics.light()
                    dismiss()
                    onOpenSupportChat()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "headphones")
                            .font(.system(size: 17, weight: .semibold))
                        Text(l10n.isRu ? "Написать в Flux Support" : "Contact Flux Support")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(FluxColors.gradient)
                    )
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.98))
                .padding(.top, 16)
            }
            .padding(EdgeInsets(top: 0, leading: 20, bottom: 28, trailing: 20))
        }
        .background(Material.ultraThinMaterial)
    }

    private func benefitRow(emoji: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FluxColors.gradientSoft)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(emoji)
                        .font(.system(size: 20))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FluxColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(FluxColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}
