import SwiftUI

/// Marketplace: buy additional usernames, list yours for sale, cancel
/// listings. The primary account username is never sellable.
struct MarketplaceView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    @State private var showListSheet = false
    @State private var confirmBuy: MarketplaceListing?
    @State private var toast: Toast?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                introCard
                myUsernamesCard
                listingsCard
            }
            .padding(EdgeInsets(top: 16, leading: 8, bottom: 32, trailing: 8))
        }
        .background(FluxColors.background.ignoresSafeArea())
        .navigationTitle("Marketplace")
        .navigationBarTitleDisplayMode(.inline)
        .fluxToast($toast)
        .sheet(isPresented: $showListSheet) {
            ListUsernameSheet { result in
                toast = Toast(text: result)
            }
        }
        .sheet(item: $confirmBuy) { listing in
            buySheet(listing)
                .presentationDetents([.height(340)])
        }
    }

    private var introCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FluxColors.gradient)
                    .frame(width: 44, height: 44)
                Image(systemName: "storefront.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Marketplace username")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(FluxColors.textPrimary)
                Text("Покупайте и продавайте дополнительные @username за Flux Coins. Основной username аккаунта не продаётся.")
                    .font(.system(size: 13))
                    .foregroundStyle(FluxColors.textSecondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FluxColors.surface)
        )
        .padding(.horizontal, 4)
    }

    private var myUsernamesCard: some View {
        VStack(spacing: 0) {
            FluxSectionTitle(text: "Мои username")
                .padding(.horizontal, -8)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(FluxColors.blueSoft)
                            .frame(width: 38, height: 38)
                        Image(systemName: "at")
                            .font(.system(size: 16))
                            .foregroundStyle(FluxColors.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(backend.me?.username ?? "—")")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(FluxColors.textPrimary)
                        Text("Основной · не продаётся")
                            .font(.system(size: 12.5))
                            .foregroundStyle(FluxColors.textTertiary)
                    }
                    Spacer()
                }
                .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))

                ForEach(backend.additionalUsernames, id: \.username) { entry in
                    Divider().overlay(FluxColors.separator).padding(.leading, 64)
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(FluxColors.violetSoft)
                                .frame(width: 38, height: 38)
                            Image(systemName: "at")
                                .font(.system(size: 16))
                                .foregroundStyle(FluxColors.violet)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(entry.username)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(FluxColors.textPrimary)
                            Text("Дополнительный · с \(formatDayDivider(entry.acquiredAtMs))")
                                .font(.system(size: 12.5))
                                .foregroundStyle(FluxColors.textTertiary)
                        }
                        Spacer()
                        Button {
                            Haptics.light()
                            showListSheet = true
                        } label: {
                            Text("Продать")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(FluxColors.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(FluxColors.blueSoft))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                }

                if backend.additionalUsernames.isEmpty {
                    Text("Дополнительных username пока нет — купите первый на marketplace ниже")
                        .font(.system(size: 13))
                        .foregroundStyle(FluxColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(FluxColors.surface)
            )
            .padding(.horizontal, 4)
        }
    }

    private var myActiveListingIds: Set<String> {
        Set(backend.marketplaceListings.filter { $0.sellerId == backend.me?.id }.map { $0.id })
    }

    private var listingsCard: some View {
        VStack(spacing: 0) {
            FluxSectionTitle(text: "Активные лоты · \(backend.marketplaceListings.count)")
                .padding(.horizontal, -8)
            VStack(spacing: 0) {
                if backend.marketplaceListings.isEmpty {
                    VStack(spacing: 8) {
                        Text("🏷️")
                            .font(.system(size: 30))
                        Text("Лотов пока нет")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(FluxColors.textPrimary)
                        Text("Выставите свой дополнительный username на продажу")
                            .font(.system(size: 13))
                            .foregroundStyle(FluxColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    ForEach(Array(backend.marketplaceListings.enumerated()), id: \.element.id) { index, listing in
                        if index > 0 {
                            Divider().overlay(FluxColors.separator).padding(.leading, 64)
                        }
                        listingRow(listing)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(FluxColors.surface)
            )
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func listingRow(_ listing: MarketplaceListing) -> some View {
        let isMine = listing.sellerId == backend.me?.id
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FluxColors.warning.opacity(0.13))
                    .frame(width: 38, height: 38)
                Image(systemName: "tag.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(FluxColors.warning)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(listing.username)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FluxColors.textPrimary)
                Text("Продавец: \(isMine ? "вы" : listing.sellerName)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(FluxColors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if isMine {
                Button {
                    Haptics.medium()
                    Task {
                        await backend.cancelListing(listing.id)
                        toast = Toast(text: "Лот снят с продажи")
                    }
                } label: {
                    Text("Снять")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FluxColors.danger)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(FluxColors.danger.opacity(0.12)))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Haptics.light()
                    confirmBuy = listing
                } label: {
                    HStack(spacing: 4) {
                        Text("\(listing.price) 🪙")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(FluxColors.gradient))
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
    }

    private func buySheet(_ listing: MarketplaceListing) -> some View {
        VStack(spacing: 14) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            Text("Купить username")
                .font(.system(size: 18, weight: .heavy))
            Text("@\(listing.username)")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(FluxColors.blue)
            Text("у \(listing.sellerName) за \(listing.price) монет?")
                .font(.system(size: 14))
                .foregroundStyle(FluxColors.textSecondary)
            Text("Баланс после покупки: \(max(0, backend.fluxCoins - listing.price)) 🪙")
                .font(.system(size: 13))
                .foregroundStyle(FluxColors.textTertiary)
            FluxButton(title: "Купить за \(listing.price) 🪙", enabled: backend.fluxCoins >= listing.price) {
                Task {
                    do {
                        try await backend.buyUsername(listing.id)
                        Haptics.success()
                        confirmBuy = nil
                        toast = Toast(text: "Username @\(listing.username) теперь ваш!")
                    } catch {
                        toast = Toast(text: error.localizedDescription, isError: true)
                    }
                }
            }
            .padding(.horizontal, 20)
            if backend.fluxCoins < listing.price {
                Text("Недостаточно монет")
                    .font(.system(size: 12))
                    .foregroundStyle(FluxColors.danger)
            }
            Spacer(minLength: 12)
        }
        .background(FluxColors.background.ignoresSafeArea())
    }
}

/// Sheet for listing one of the owned additional usernames for sale.
struct ListUsernameSheet: View {
    @EnvironmentObject var backend: LocalBackend
    @Environment(\.dismiss) private var dismiss

    let onResult: (String) -> Void

    @State private var selectedUsername = ""
    @State private var priceText = ""
    @State private var errorText: String?
    @State private var listing = false

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            Text("Выставить на продажу")
                .font(.system(size: 18, weight: .heavy))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            if backend.additionalUsernames.isEmpty {
                Text("У вас нет дополнительных username для продажи.\nКупите их на marketplace.")
                    .font(.system(size: 14))
                    .foregroundStyle(FluxColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
            } else {
                VStack(spacing: 8) {
                    Text("Username")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FluxColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(backend.additionalUsernames, id: \.username) { entry in
                                let isSelected = selectedUsername == entry.username
                                Button {
                                    Haptics.selection()
                                    selectedUsername = entry.username
                                } label: {
                                    Text("@\(entry.username)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(isSelected ? .white : FluxColors.textPrimary)
                                        .padding(.horizontal, 12)
                                        .frame(height: 36)
                                        .background(
                                            Capsule().fill(isSelected ? AnyShapeStyle(FluxColors.gradient) : AnyShapeStyle(FluxColors.surfaceGray))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Text("Цена (монет)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FluxColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                    FluxTextField(text: $priceText, hint: "Например, 500", keyboard: .numberPad)
                        .padding(.horizontal, 20)
                        .keyboardType(.numberPad)
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FluxColors.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                }

                FluxButton(title: "Выставить на продажу", enabled: !selectedUsername.isEmpty && Int(priceText) != nil && !listing, showsProgress: listing) {
                    guard let price = Int(priceText) else { return }
                    listing = true
                    Task {
                        do {
                            _ = try await backend.listUsernameForSale(username: selectedUsername, price: price)
                            listing = false
                            dismiss()
                            onResult("Лот @\(selectedUsername) выставлен за \(price) 🪙")
                        } catch {
                            listing = false
                            errorText = error.localizedDescription
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer(minLength: 16)
        }
        .background(FluxColors.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear {
            selectedUsername = backend.additionalUsernames.first?.username ?? ""
        }
    }
}
