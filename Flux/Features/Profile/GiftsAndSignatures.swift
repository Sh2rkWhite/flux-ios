import SwiftUI

/// Gift catalog with rarity filters, live coin balance and the send flow
/// (mirrors the Android GiftCatalogSheet).
struct GiftCatalogSheet: View {
    @EnvironmentObject var backend: LocalBackend
    @Environment(\.dismiss) private var dismiss

    let recipient: FluxUser
    let onSent: (FluxGift) -> Void

    @State private var selected: GiftCatalogItem?
    @State private var message = ""
    @State private var rarityFilter: GiftRarity?
    @State private var sending = false
    @State private var errorText: String?

    private var filteredGifts: [GiftCatalogItem] {
        guard let rarityFilter else { return GiftCatalog.all }
        return GiftCatalog.all.filter { $0.rarity == rarityFilter }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xFFB020), Color(hex: 0xFF6B00)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                    .overlay(Text("🎁").font(.system(size: 20)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Отправить подарок")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(FluxColors.textPrimary)
                    Text(recipient.name)
                        .font(.system(size: 13))
                        .foregroundStyle(FluxColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("🪙 \(backend.fluxCoins)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FluxColors.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(FluxColors.warning.opacity(0.12))
                            .overlay(Capsule().strokeBorder(FluxColors.warning.opacity(0.3), lineWidth: 1))
                    )
                Button {
                    dismiss()
                } label: {
                    ZStack {
                        Circle().fill(FluxColors.surfaceGray)
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FluxColors.textSecondary)
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 12, trailing: 20))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "Все", color: FluxColors.blue, isActive: rarityFilter == nil) {
                        rarityFilter = nil
                    }
                    ForEach(GiftRarity.allCases, id: \.self) { rarity in
                        filterChip(title: rarity.label, color: rarity.color, isActive: rarityFilter == rarity) {
                            rarityFilter = rarityFilter == rarity ? nil : rarity
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(filteredGifts) { item in
                        giftCell(item)
                    }
                }
                .padding(16)
            }

            if let selected {
                sendPanel(selected)
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FluxColors.danger)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .background(FluxColors.background.ignoresSafeArea())
    }

    private func filterChip(title: String, color: Color, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(FluxMotion.springAnimation) { action() }
        } label: {
            Text(title)
                .font(.system(size: 13, isActive ? .bold : .medium))
                .foregroundStyle(isActive ? color : FluxColors.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    Capsule()
                        .fill(isActive ? color.opacity(0.15) : FluxColors.surfaceGray)
                        .overlay(Capsule().strokeBorder(isActive ? color.opacity(0.5) : .clear, lineWidth: 1.5))
                )
        }
        .buttonStyle(.plain)
    }

    private func giftCell(_ item: GiftCatalogItem) -> some View {
        let isSelected = selected?.id == item.id
        return Button {
            Haptics.light()
            withAnimation(FluxMotion.springAnimation) {
                selected = isSelected ? nil : item
            }
        } label: {
            VStack(spacing: 5) {
                Circle()
                    .fill(LinearGradient(colors: item.rarity.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.18))
                    .frame(width: 44, height: 44)
                    .overlay(Text(item.emoji).font(.system(size: 22)))
                Text(item.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(FluxColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(item.cost) 🪙")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(item.rarity.color)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(0.82, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FluxColors.cardSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? item.rarity.color.opacity(0.7) : item.rarity.color.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(item.rarity.color)
                        .background(Circle().fill(FluxColors.background))
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func sendPanel(_ item: GiftCatalogItem) -> some View {
        VStack(spacing: 12) {
            Divider().overlay(FluxColors.separator)
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: item.rarity.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.2))
                    .frame(width: 52, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14).strokeBorder(item.rarity.color.opacity(0.4), lineWidth: 1)
                    )
                    .overlay(Text(item.emoji).font(.system(size: 24)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FluxColors.textPrimary)
                    Text("\(item.cost) 🪙")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item.rarity.color)
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            TextField("Добавить сообщение (необязательно)...", text: $message, axis: .vertical)
                .lineLimit(1...2)
                .font(.system(size: 14))
                .foregroundStyle(FluxColors.textPrimary)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(FluxColors.surfaceGray)
                )
                .padding(.horizontal, 16)
                .onChange(of: message) { newValue in
                    if newValue.count > 100 {
                        message = String(newValue.prefix(100))
                    }
                }

            Button {
                send(item)
            } label: {
                HStack(spacing: 8) {
                    if sending {
                        ProgressView().tint(.white)
                    } else {
                        Text(item.emoji).font(.system(size: 18))
                        Text("Отправить подарок")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: item.rarity.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: item.rarity.color.opacity(0.35), radius: 12, y: 4)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(sending)
            .padding(EdgeInsets(top: 0, leading: 16, bottom: 24, trailing: 16))
        }
        .background(FluxColors.surface)
    }

    private func send(_ item: GiftCatalogItem) {
        guard !sending else { return }
        sending = true
        errorText = nil
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let gift = try await backend.sendGift(
                    toUserId: recipient.id,
                    catalogId: item.id,
                    message: note.isEmpty ? nil : note
                )
                Haptics.success()
                sending = false
                dismiss()
                onSent(gift)
            } catch {
                sending = false
                errorText = "Ошибка отправки: \(error.localizedDescription)"
            }
        }
    }
}

/// Full-screen confirmation shown after a successful gift send.
struct GiftSentOverlay: View {
    @Environment(\.dismiss) private var dismiss

    let gift: FluxGift
    let recipientName: String

    @State private var floatUp = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [gift.rarity.color.opacity(0.35), .clear],
                                center: .center, startRadius: 10, endRadius: 90)
                        )
                        .frame(width: 110, height: 110)
                    Circle()
                        .fill(LinearGradient(colors: gift.rarity.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.25))
                        .frame(width: 76, height: 76)
                        .overlay(Circle().strokeBorder(gift.rarity.color.opacity(0.5), lineWidth: 2))
                    Text(gift.emoji)
                        .font(.system(size: 36))
                }
                .offset(y: floatUp ? -6 : 6)
                .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: floatUp)

                Text("Подарок отправлен!")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(colors: gift.rarity.gradientColors, startPoint: .leading, endPoint: .trailing)
                    )
                Text("\(gift.emoji) \(gift.name)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("для \(recipientName)")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0x9AA1B5))
                Text(gift.rarity.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(gift.rarity.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(gift.rarity.color.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(gift.rarity.color.opacity(0.35), lineWidth: 1))
                if let message = gift.message, !message.isEmpty {
                    Text("«\(message)»")
                        .font(.system(size: 13).italic())
                        .foregroundStyle(Color(hex: 0xD0D4E8))
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(hex: 0x1A1E2A))
                        )
                }
                Text("Нажмите, чтобы закрыть")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(28)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color(hex: 0x0E1016))
                    .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(gift.rarity.color.opacity(0.45), lineWidth: 1.5))
                    .shadow(color: gift.rarity.color.opacity(0.35), radius: 40, y: 4)
            )
        }
        .onTapGesture { dismiss() }
        .onAppear {
            floatUp = true
            Task {
                try? await Task.sleep(nanoseconds: 3_800_000_000)
                dismiss()
            }
        }
    }
}

// MARK: - Signature composer & settings

/// «Оставить подпись» composer — sends a pending signature to the owner's
/// guestbook.
struct SignatureComposerSheet: View {
    @EnvironmentObject var backend: LocalBackend
    @Environment(\.dismiss) private var dismiss

    let recipient: FluxUser
    let onResult: (String) -> Void

    @State private var text = ""
    @State private var sending = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)

            HStack(spacing: 12) {
                FluxAvatarView(user: recipient, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Оставить подпись")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(FluxColors.textPrimary)
                    Text("в гостевой книге \(recipient.name)")
                        .font(.system(size: 13))
                        .foregroundStyle(FluxColors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            TextField("Ваша подпись...", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .font(.system(size: 16))
                .foregroundStyle(FluxColors.textPrimary)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(FluxColors.surfaceGray)
                )
                .padding(.horizontal, 20)
                .onChange(of: text) { newValue in
                    if newValue.count > 200 {
                        text = String(newValue.prefix(200))
                    }
                }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FluxColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }

            FluxButton(title: "Отправить подпись", enabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending, showsProgress: sending) {
                sending = true
                errorText = nil
                Task {
                    do {
                        try await backend.sendSignature(profileOwnerId: recipient.id, text: text)
                        sending = false
                        dismiss()
                        onResult("Подпись отправлена — владелец должен её принять")
                    } catch {
                        sending = false
                        errorText = error.localizedDescription
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 16)
        }
        .background(FluxColors.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

/// Own-profile signature settings: manual approval (default), auto-accept,
/// forbid signatures.
struct SignatureSettingsSheet: View {
    @EnvironmentObject var backend: LocalBackend
    @Environment(\.dismiss) private var dismiss

    @State private var visibility = ProfileVisibility()

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            Text("Настройки подписей")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(FluxColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 18, leading: 20, bottom: 8, trailing: 20))

            VStack(spacing: 0) {
                FluxSettingsTile(
                    icon: "checkmark.shield",
                    title: "Ручное подтверждение",
                    subtitle: "Подписи публикуются после вашего одобрения",
                    iconColor: FluxColors.blue
                ) {
                    visibility.requireSignatureApproval = true
                    apply()
                }
                .overlay(alignment: .trailing) {
                    if visibility.requireSignatureApproval && visibility.allowSignatures {
                        checkmark
                    }
                }
                Divider().padding(.leading, 66)

                FluxSettingsTile(
                    icon: "bolt.badge.checkmark",
                    title: "Автоматическое принятие",
                    subtitle: "Подписи публикуются сразу",
                    iconColor: FluxColors.online,
                    iconBackground: FluxColors.online.opacity(0.12)
                ) {
                    visibility.requireSignatureApproval = false
                    visibility.allowSignatures = true
                    apply()
                }
                .overlay(alignment: .trailing) {
                    if !visibility.requireSignatureApproval && visibility.allowSignatures {
                        checkmark
                    }
                }
                .padding(.trailing, 14)

                Divider().padding(.leading, 66)

                FluxSettingsTile(
                    icon: "nosign",
                    title: "Запретить подписи",
                    subtitle: "Никто не сможет оставить подпись",
                    iconColor: FluxColors.danger,
                    iconBackground: FluxColors.danger.opacity(0.1)
                ) {
                    visibility.allowSignatures.toggle()
                    apply()
                }
                .overlay(alignment: .trailing) {
                    if !visibility.allowSignatures {
                        checkmark
                    }
                }
            }
            .padding(12)

            Spacer(minLength: 16)
        }
        .background(FluxColors.background.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear {
            visibility = backend.profileVisibility
        }
    }

    private var checkmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 20))
            .foregroundStyle(FluxColors.online)
            .padding(.trailing, 14)
    }

    private func apply() {
        Haptics.selection()
        let next = visibility
        Task { await backend.updateVisibility(next) }
    }
}
