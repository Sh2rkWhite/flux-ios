import SwiftUI

/// Payload of the FluxCoinsBot receipt dialog (mirrors the Dart
/// `_showReceiptDialog`).
struct BotReceipt: Identifiable {
    let title: String
    let amount: String
    let detail: String
    let transactionId: String

    var id: String { "\(title)-\(transactionId)" }
}

/// FluxCoinsBot (@FluxCoinsBot) — the in-app coins bot in the spirit of the
/// Telegram Crypto Bot, working exclusively with Flux Coins.
///
/// Balance, transfers, one-time checks, P2P marketplace with escrow,
/// transaction history and quick-transfer QR. All operations execute on the
/// shared backend (atomic Firestore transactions); both iOS and Android use
/// the same ledger and the same balance. Mirrors the Flutter
/// `coins_bot_screen.dart`.
struct CoinsBotView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Pre-filled recipient (FluxID) — set when opened from a payment QR.
    var sendTo: String? = nil
    /// Pre-filled amount — set when opened from a payment QR.
    var sendAmount: Int? = nil

    private enum BotSheet: String, Identifiable {
        case send, receive, checks, p2p, balance, security
        var id: String { rawValue }
    }

    @State private var sheet: BotSheet?
    @State private var sendPrefillTo: String?
    @State private var sendPrefillAmount: Int?
    @State private var receipt: BotReceipt?
    @State private var toast: Toast?

    /// The bot contact. Created on appear via `ensureCoinsBot()`; during
    /// render a static fallback keeps the view free of side effects.
    private var botUser: FluxUser {
        backend.userById(FluxUser.coinsBotId) ?? FluxUser(
            id: FluxUser.coinsBotId,
            fluxId: "FLX-COINS",
            name: "Flux Coins",
            username: "FluxCoinsBot",
            status: "Баланс · переводы · P2P · чеки",
            isOnline: true,
            isVerified: true
        )
    }

    var body: some View {
        ZStack {
            // Soft ambient gradient behind the glass.
            LinearGradient(
                colors: [
                    FluxColors.warning.opacity(colorScheme == .dark ? 0.14 : 0.10),
                    .clear,
                    FluxColors.blue.opacity(colorScheme == .dark ? 0.10 : 0.07),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    balanceHero
                        .padding(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))
                    menuGrid
                        .padding(EdgeInsets(top: 16, leading: 20, bottom: 0, trailing: 20))
                    recentHeader
                        .padding(EdgeInsets(top: 22, leading: 20, bottom: 0, trailing: 20))
                    recentList
                        .padding(EdgeInsets(top: 10, leading: 20, bottom: 34, trailing: 20))
                }
            }
        }
        .background(FluxColors.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .fluxToast($toast)
        .onAppear {
            backend.ensureCoinsBot()
            if let sendTo {
                // Mirrors the Dart post-frame callback: open the send sheet
                // with the QR prefill once the screen is visible.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    openSendSheet(prefillTo: sendTo, prefillAmount: sendAmount)
                }
            }
        }
        .sheet(item: $sheet) { current in
            botSheetContent(current)
        }
        .overlay {
            if let receipt {
                receiptOverlay(receipt)
            }
        }
        .animation(FluxMotion.decelAnimation, value: receipt?.id)
    }

    // MARK: Sheet routing

    @ViewBuilder
    private func botSheetContent(_ current: BotSheet) -> some View {
        switch current {
        case .send:
            CoinsBotSendSheet(
                prefillTo: sendPrefillTo,
                prefillAmount: sendPrefillAmount,
                onReceipt: presentReceipt
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        case .receive:
            CoinsBotReceiveSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        case .checks:
            CoinsBotChecksSheet(onReceipt: presentReceipt)
                .presentationDetents([.fraction(0.78)])
                .presentationDragIndicator(.hidden)
        case .p2p:
            CoinsBotP2pSheet()
                .presentationDetents([.fraction(0.82)])
                .presentationDragIndicator(.hidden)
        case .balance:
            CoinsBotBalanceSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
        case .security:
            CoinsBotSecuritySheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
        }
    }

    private func openSendSheet(prefillTo: String? = nil, prefillAmount: Int? = nil) {
        Haptics.light()
        sendPrefillTo = prefillTo
        sendPrefillAmount = prefillAmount
        sheet = .send
    }

    /// The receipt is shown on the bot screen after the action sheet closed
    /// (mirrors the Dart pop-then-showDialog flow).
    private func presentReceipt(_ value: BotReceipt) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            Haptics.success()
            receipt = value
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(FluxColors.textPrimary)
                    .padding(10)
            }
            .buttonStyle(ScaleButtonStyle())

            FluxAvatarView(user: botUser, size: 42)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(botUser.name)
                        .font(.system(size: 16.5, weight: .bold))
                        .foregroundStyle(FluxColors.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(FluxColors.blue)
                }
                Text("@\(botUser.username ?? "FluxCoinsBot") · бот")
                    .font(.system(size: 13))
                    .foregroundStyle(FluxColors.textSecondary)
            }
            Spacer()
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 20))
    }

    // MARK: Balance hero

    private var balanceHero: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("🪙")
                    .font(.system(size: 26))
                Text("\(backend.fluxCoins)")
                    .font(.system(size: 38, weight: .heavy).monospacedDigit())
                    .foregroundStyle(FluxColors.warning)
            }
            .frame(maxWidth: .infinity)
            Text(pluralRu(backend.fluxCoins, "Flux Coin", "Flux Coins", "Flux Coins"))
                .font(.system(size: 13.5))
                .foregroundStyle(FluxColors.textSecondary)
                .padding(.top, 2)

            HStack(spacing: 10) {
                heroAction(icon: "arrow.up", label: "Отправить") {
                    openSendSheet()
                }
                heroAction(icon: "arrow.down", label: "Получить") {
                    Haptics.light()
                    sheet = .receive
                }
            }
            .padding(.top, 16)
        }
        .padding(22)
        .glassCard(cornerRadius: 28)
    }

    private func heroAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 14.5, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FluxColors.gradient)
            )
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.96))
    }

    // MARK: Menu grid

    private var menuGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                menuTile(emoji: "💰", label: "Баланс") {
                    Haptics.light()
                    sheet = .balance
                }
                menuTile(emoji: "↔️", label: "P2P") {
                    Haptics.light()
                    sheet = .p2p
                }
            }
            HStack(spacing: 10) {
                menuTile(emoji: "🎟", label: "Чеки") {
                    Haptics.light()
                    sheet = .checks
                }
                menuTile(emoji: "📤", label: "Отправить") {
                    openSendSheet()
                }
            }
            HStack(spacing: 10) {
                menuTile(emoji: "📥", label: "Получить") {
                    Haptics.light()
                    sheet = .receive
                }
                NavigationLink(value: Route.fluxCoins) {
                    menuTileContent(emoji: "📜", label: "История")
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.96))
            }
            HStack(spacing: 10) {
                menuTile(emoji: "⚙️", label: "Настройки") {
                    Haptics.light()
                    sheet = .security
                }
                menuTile(emoji: "🛡", label: "Безопасность") {
                    Haptics.light()
                    sheet = .security
                }
            }
        }
    }

    private func menuTile(emoji: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            menuTileContent(emoji: emoji, label: label)
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.96))
    }

    private func menuTileContent(emoji: String, label: String) -> some View {
        HStack(spacing: 10) {
            Text(emoji)
                .font(.system(size: 22))
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FluxColors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .glassCard(cornerRadius: 22)
    }

    // MARK: Recent activity

    private var recentHeader: some View {
        HStack {
            Text("Последние операции")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FluxColors.textSecondary)
            Spacer()
            NavigationLink(value: Route.fluxCoins) {
                Text("Все")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FluxColors.blue)
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.96))
        }
    }

    private var recentList: some View {
        let txs = Array(backend.coinTransactions.prefix(3))
        return Group {
            if txs.isEmpty {
                Text("Операций пока нет")
                    .font(.system(size: 14))
                    .foregroundStyle(FluxColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .glassCard(cornerRadius: 22)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(txs.enumerated()), id: \.element.id) { index, tx in
                        CoinsBotTxRow(tx: tx)
                        if index < txs.count - 1 {
                            Divider()
                                .overlay(FluxColors.separator)
                                .padding(.leading, 62)
                        }
                    }
                }
                .padding(.vertical, 4)
                .glassCard(cornerRadius: 22)
            }
        }
    }

    // MARK: Receipt dialog

    private func receiptOverlay(_ receipt: BotReceipt) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { self.receipt = nil }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("✅")
                    Text(receipt.title)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(FluxColors.textPrimary)
                }
                Text(receipt.amount)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(FluxColors.textPrimary)
                    .padding(.top, 10)
                Text(receipt.detail)
                    .font(.system(size: 13.5))
                    .foregroundStyle(FluxColors.textSecondary)
                    .padding(.top, 4)
                Text("Transaction ID")
                    .font(.system(size: 12))
                    .foregroundStyle(FluxColors.textTertiary)
                    .padding(.top, 12)
                Text(receipt.transactionId)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(FluxColors.textPrimary)
                    .lineLimit(2)
                    .padding(.top, 2)

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = receipt.transactionId
                        Haptics.selection()
                        self.receipt = nil
                    } label: {
                        Text("Скопировать ID")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(FluxColors.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(FluxColors.blueSoft)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle(scale: 0.96))

                    Button {
                        self.receipt = nil
                    } label: {
                        Text("Готово")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(FluxColors.gradient)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle(scale: 0.96))
                }
                .padding(.top, 16)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(FluxColors.surface)
                    .shadow(color: .black.opacity(0.2), radius: 30, y: 8)
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }
}

// MARK: - Transaction row

/// A single ledger row in the bot's «Последние операции» block
/// (mirrors the Dart `_TxRow`).
struct CoinsBotTxRow: View {
    let tx: CoinTransaction

    private var icon: String {
        switch tx.type {
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

    var body: some View {
        let positive = tx.amount > 0
        let color = positive ? FluxColors.online : FluxColors.danger
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(color.opacity(positive ? 0.12 : 0.10))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(color)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(tx.description.isEmpty ? tx.type.label : tx.description)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(FluxColors.textPrimary)
                    .lineLimit(1)
                Text(formatChatTime(tx.timestampMs))
                    .font(.system(size: 12))
                    .foregroundStyle(FluxColors.textTertiary)
            }
            Spacer(minLength: 8)
            Text(positive ? "+\(tx.amount)" : "\(tx.amount)")
                .font(.system(size: 14.5, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Shared sheet pieces

/// Sheet header with emoji, title and optional subtitle (mirrors the Dart
/// `_SheetHeader`; the grabber is added by each sheet).
struct CoinsBotSheetHeader: View {
    let emoji: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(emoji)
                    .font(.system(size: 24))
                Text(title)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(FluxColors.textPrimary)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(FluxColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 10, trailing: 20))
    }
}

/// Simple segmented tab bar for the sheets (mirrors the Dart `TabBar`).
struct CoinsBotTabBar: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Button {
                    Haptics.selection()
                    withAnimation(FluxMotion.decelAnimation) { selection = index }
                } label: {
                    VStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(selection == index ? FluxColors.blue : FluxColors.textSecondary)
                        Capsule()
                            .fill(selection == index ? FluxColors.blue : .clear)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }
}

/// Gradient primary CTA inside the bot sheets (mirrors `_PrimaryButton`).
struct CoinsBotPrimaryButton: View {
    let title: String
    var busy = false
    let action: () -> Void

    var body: some View {
        Button {
            guard !busy else { return }
            Haptics.light()
            action()
        } label: {
            Group {
                if busy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Group {
                    if busy {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(FluxColors.textTertiary.opacity(0.3))
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(FluxColors.gradient)
                    }
                }
            )
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.97))
        .disabled(busy)
    }
}

// MARK: - 📤 Отправить

struct CoinsBotSendSheet: View {
    @EnvironmentObject var backend: LocalBackend
    @Environment(\.dismiss) private var dismiss

    var prefillTo: String? = nil
    var prefillAmount: Int? = nil
    let onReceipt: (BotReceipt) -> Void

    @State private var toText = ""
    @State private var amountText = ""
    @State private var busy = false
    @State private var toast: Toast?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            CoinsBotSheetHeader(
                emoji: "📤",
                title: "Отправить Flux Coins",
                subtitle: "Перевод выполняется атомарно на общем балансе Flux"
            )
            VStack(alignment: .leading, spacing: 0) {
                Text("Получатель")
                    .font(.system(size: 13))
                    .foregroundStyle(FluxColors.textSecondary)
                FluxTextField(text: $toText, hint: "FLX-XXXXXXXX или @username")
                    .padding(.top, 6)

                HStack {
                    Text("Сумма")
                        .font(.system(size: 13))
                        .foregroundStyle(FluxColors.textSecondary)
                    Spacer()
                    Text("Баланс: \(backend.fluxCoins)")
                        .font(.system(size: 13))
                        .foregroundStyle(FluxColors.textTertiary)
                }
                .padding(.top, 14)
                FluxTextField(text: $amountText, hint: "Например, 100", keyboard: .numberPad)
                    .padding(.top, 6)

                CoinsBotPrimaryButton(title: "Отправить", busy: busy, action: send)
                    .padding(.top, 18)
            }
            .padding(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
            Spacer(minLength: 16)
        }
        .background(FluxColors.background.ignoresSafeArea())
        .fluxToast($toast)
        .onAppear {
            toText = prefillTo ?? ""
            if let prefillAmount { amountText = "\(prefillAmount)" }
        }
    }

    private func send() {
        guard let amount = Int(amountText.trimmingCharacters(in: .whitespaces)), amount > 0 else {
            toast = Toast(text: "Введите сумму больше нуля", isError: true)
            return
        }
        var target = toText.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else {
            toast = Toast(text: "Укажите FluxID или @username получателя", isError: true)
            return
        }
        busy = true
        Task {
            do {
                // Resolve @username → FluxID through the shared directory.
                if target.hasPrefix("@") {
                    if let user = await backend.lookupUsername(String(target.dropFirst())) {
                        target = user.fluxId
                    } else {
                        busy = false
                        toast = Toast(text: "Пользователь \(target) не найден", isError: true)
                        return
                    }
                }
                let myFluxId = backend.me?.fluxId ?? ""
                if target.uppercased() == myFluxId.uppercased() {
                    busy = false
                    toast = Toast(text: "Нельзя перевести самому себе", isError: true)
                    return
                }
                let txId = try await backend.coinsTransfer(toFluxId: target, amount: amount)
                dismiss()
                onReceipt(BotReceipt(
                    title: "Перевод выполнен",
                    amount: "\(amount) 🪙",
                    detail: "Получатель: \(target)",
                    transactionId: txId
                ))
            } catch {
                busy = false
                toast = Toast(text: error.localizedDescription, isError: true)
            }
        }
    }
}

// MARK: - 📥 Получить

struct CoinsBotReceiveSheet: View {
    @EnvironmentObject var backend: LocalBackend

    @State private var amountText = ""
    @State private var toast: Toast?

    var body: some View {
        let myFluxId = backend.myFluxId
        let amount = Int(amountText.trimmingCharacters(in: .whitespaces))
        let payload = QRCodeGenerator.payPayload(fluxId: myFluxId, amount: amount)

        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            CoinsBotSheetHeader(
                emoji: "📥",
                title: "Получить Flux Coins",
                subtitle: "Покажите QR или отправьте свой FluxID"
            )
            if let image = QRCodeGenerator.qrImage(for: payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.white)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 16, y: 6)
                    .padding(.top, 10)
            }
            Text(amount != nil && amount! > 0 ? "QR на сумму \(amount!) 🪙" : "QR на любую сумму")
                .font(.system(size: 13))
                .foregroundStyle(FluxColors.textSecondary)
                .padding(.top, 6)

            FluxTextField(text: $amountText, hint: "Сумма (необязательно)", keyboard: .numberPad)
                .padding(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))

            Button {
                UIPasteboard.general.string = myFluxId
                Haptics.selection()
                toast = Toast(text: "FluxID скопирован")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15))
                    Text(myFluxId)
                        .font(.system(size: 14.5, weight: .bold))
                }
                .foregroundStyle(FluxColors.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(FluxColors.blueSoft)
                )
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.97))
            .padding(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
            Spacer(minLength: 16)
        }
        .background(FluxColors.background.ignoresSafeArea())
        .fluxToast($toast)
    }
}

// MARK: - 🎟 Чеки

struct CoinsBotChecksSheet: View {
    @EnvironmentObject var backend: LocalBackend

    let onReceipt: (BotReceipt) -> Void

    @State private var tab = 0
    @State private var toast: Toast?

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            CoinsBotSheetHeader(
                emoji: "🎟",
                title: "Чеки",
                subtitle: "Одноразовые ваучеры Flux Coins: создать, получить, отменить"
            )
            CoinsBotTabBar(titles: ["Создать", "Мои чеки", "Погасить"], selection: $tab)

            switch tab {
            case 0:
                ScrollView(showsIndicators: false) {
                    CoinsBotCreateCheckTab(onReceipt: onReceipt, onToast: { toast = $0 })
                        .padding(EdgeInsets(top: 16, leading: 20, bottom: 24, trailing: 20))
                }
            case 1:
                CoinsBotMyChecksTab(onToast: { toast = $0 })
            default:
                ScrollView(showsIndicators: false) {
                    CoinsBotRedeemCheckTab(onReceipt: onReceipt, onToast: { toast = $0 })
                        .padding(EdgeInsets(top: 16, leading: 20, bottom: 24, trailing: 20))
                }
            }
        }
        .background(FluxColors.background.ignoresSafeArea())
        .fluxToast($toast)
    }
}

struct CoinsBotCreateCheckTab: View {
    @EnvironmentObject var backend: LocalBackend
    @Environment(\.dismiss) private var dismiss

    let onReceipt: (BotReceipt) -> Void
    let onToast: (Toast) -> Void

    @State private var amountText = ""
    @State private var recipientText = ""
    @State private var ttlMs: Int?
    @State private var busy = false

    private let ttlOptions: [(String, Int?)] = [
        ("Без срока", nil),
        ("1 час", 60 * 60 * 1000),
        ("24 часа", 24 * 60 * 60 * 1000),
        ("7 дней", 7 * 24 * 60 * 60 * 1000),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Сумма")
                .font(.system(size: 13))
                .foregroundStyle(FluxColors.textSecondary)
            FluxTextField(text: $amountText, hint: "Например, 100", keyboard: .numberPad)
                .padding(.top, 6)

            Text("Получатель (необязательно)")
                .font(.system(size: 13))
                .foregroundStyle(FluxColors.textSecondary)
                .padding(.top, 14)
            FluxTextField(text: $recipientText, hint: "FLX-XXXXXXXX — пусто = любой")
                .padding(.top, 6)

            Text("Срок действия")
                .font(.system(size: 13))
                .foregroundStyle(FluxColors.textSecondary)
                .padding(.top, 14)
            FlowLayout(spacing: 8) {
                ForEach(Array(ttlOptions.enumerated()), id: \.offset) { _, option in
                    ttlChip(label: option.0, value: option.1)
                }
            }
            .padding(.top, 8)

            CoinsBotPrimaryButton(title: "Создать чек", busy: busy, action: create)
                .padding(.top, 20)
        }
    }

    private func ttlChip(label: String, value: Int?) -> some View {
        let selected = ttlMs == value
        return Button {
            Haptics.selection()
            withAnimation(FluxMotion.decelAnimation) { ttlMs = value }
        } label: {
            Text(label)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(selected ? FluxColors.blue : FluxColors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? FluxColors.blueSoft : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? FluxColors.blue : FluxColors.separator, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func create() {
        guard let amount = Int(amountText.trimmingCharacters(in: .whitespaces)), amount > 0 else {
            onToast(Toast(text: "Введите сумму больше нуля", isError: true))
            return
        }
        let recipient = recipientText.trimmingCharacters(in: .whitespaces)
        if !recipient.isEmpty, !recipient.uppercased().matchesFluxIdPattern {
            onToast(Toast(text: "FluxID получателя в формате FLX-XXXXXXXX", isError: true))
            return
        }
        busy = true
        Task {
            do {
                let check = try await backend.createCheck(
                    amount: amount,
                    recipientFluxId: recipient.isEmpty ? nil : recipient.uppercased(),
                    ttlMs: ttlMs
                )
                dismiss()
                onReceipt(BotReceipt(
                    title: "Чек создан",
                    amount: "\(amount) 🪙",
                    detail: check.recipientFluxId != nil
                        ? "Персональный чек для \(check.recipientFluxId ?? "")"
                        : "Предъявительский чек — передайте код получателю",
                    transactionId: check.id
                ))
            } catch {
                busy = false
                onToast(Toast(text: error.localizedDescription, isError: true))
            }
        }
    }
}

struct CoinsBotMyChecksTab: View {
    @EnvironmentObject var backend: LocalBackend

    let onToast: (Toast) -> Void

    var body: some View {
        if backend.myChecks.isEmpty {
            Text("Вы ещё не создали ни одного чека")
                .font(.system(size: 14))
                .foregroundStyle(FluxColors.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(backend.myChecks) { check in
                        CoinsBotCheckCard(check: check, onToast: onToast)
                    }
                }
                .padding(EdgeInsets(top: 14, leading: 20, bottom: 24, trailing: 20))
            }
        }
    }
}

struct CoinsBotCheckCard: View {
    @EnvironmentObject var backend: LocalBackend

    let check: FluxCheck
    let onToast: (Toast) -> Void

    private var nowMs: Int { Int(Date().timeIntervalSince1970 * 1000) }

    private var statusColor: Color {
        switch check.status {
        case .active: return check.isExpired(nowMs) ? FluxColors.warning : FluxColors.online
        case .redeemed: return FluxColors.blue
        case .cancelled: return FluxColors.danger
        }
    }

    var body: some View {
        let expired = check.isExpired(nowMs)
        let statusText = check.status == .active && expired ? "Истёк" : check.status.label

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(check.amount) 🪙")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(FluxColors.textPrimary)
                Spacer()
                Text(statusText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(statusColor.opacity(0.12))
                    )
            }
            Text(check.recipientFluxId != nil
                ? "Персональный · \(check.recipientFluxId ?? "")"
                : "Предъявительский")
                .font(.system(size: 13))
                .foregroundStyle(FluxColors.textSecondary)
                .padding(.top, 8)
            Text("Код: \(check.id)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(FluxColors.textTertiary)
                .lineLimit(1)
                .padding(.top, 4)

            if check.status == .active && !expired {
                HStack(spacing: 8) {
                    Button {
                        UIPasteboard.general.string = check.id
                        Haptics.selection()
                    } label: {
                        Text("Скопировать код")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(FluxColors.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(FluxColors.blueSoft)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle(scale: 0.96))

                    Button {
                        Task {
                            do {
                                try await backend.cancelCheck(check.id)
                                onToast(Toast(text: "Чек отменён, монеты возвращены"))
                            } catch {
                                onToast(Toast(text: error.localizedDescription, isError: true))
                            }
                        }
                    } label: {
                        Text("Отменить")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(FluxColors.danger)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(FluxColors.danger.opacity(0.10))
                            )
                    }
                    .buttonStyle(ScaleButtonStyle(scale: 0.96))
                }
                .padding(.top, 10)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FluxColors.surfaceGray)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(FluxColors.separator, lineWidth: 1)
        )
    }
}

struct CoinsBotRedeemCheckTab: View {
    @EnvironmentObject var backend: LocalBackend
    @Environment(\.dismiss) private var dismiss

    let onReceipt: (BotReceipt) -> Void
    let onToast: (Toast) -> Void

    @State private var codeText = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Код чека")
                .font(.system(size: 13))
                .foregroundStyle(FluxColors.textSecondary)
            FluxTextField(text: $codeText, hint: "Вставьте код чека")
                .padding(.top, 6)
            Text("Чек одноразовый: после погашения получить его повторно невозможно.")
                .font(.system(size: 12.5))
                .foregroundStyle(FluxColors.textTertiary)
                .padding(.top, 8)
            CoinsBotPrimaryButton(title: "Получить монеты", busy: busy, action: redeem)
                .padding(.top, 18)
        }
    }

    private func redeem() {
        let code = codeText.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else {
            onToast(Toast(text: "Введите код чека", isError: true))
            return
        }
        busy = true
        Task {
            do {
                let check = try await backend.redeemCheck(code)
                dismiss()
                onReceipt(BotReceipt(
                    title: "Чек погашен",
                    amount: "+\(check.amount) 🪙",
                    detail: "Монеты зачислены на ваш баланс",
                    transactionId: check.transactionId
                ))
            } catch {
                busy = false
                onToast(Toast(text: error.localizedDescription, isError: true))
            }
        }
    }
}

// MARK: - ↔️ P2P

struct CoinsBotP2pSheet: View {
    @EnvironmentObject var backend: LocalBackend

    @State private var tab = 0
    @State private var showCreateOffer = false
    @State private var toast: Toast?

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            CoinsBotSheetHeader(
                emoji: "↔️",
                title: "P2P Marketplace",
                subtitle: "Продажа Flux Coins с escrow: монеты блокируются до подтверждения сделки"
            )
            CoinsBotTabBar(titles: ["Маркет", "Мои сделки"], selection: $tab)

            if tab == 0 {
                marketTab
            } else {
                myDealsTab
            }
        }
        .background(FluxColors.background.ignoresSafeArea())
        .fluxToast($toast)
        .sheet(isPresented: $showCreateOffer) {
            CoinsBotCreateOfferSheet { toast = $0 }
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.hidden)
        }
    }

    // MARK: Маркет

    private var marketTab: some View {
        VStack(spacing: 0) {
            CoinsBotPrimaryButton(title: "+ Создать продажу") {
                showCreateOffer = true
            }
            .padding(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))

            if backend.p2pOpenOffers.isEmpty {
                Text("Нет открытых предложений")
                    .font(.system(size: 14))
                    .foregroundStyle(FluxColors.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(backend.p2pOpenOffers) { offer in
                            CoinsBotOfferCard(offer: offer) { toast = $0 }
                        }
                    }
                    .padding(EdgeInsets(top: 12, leading: 20, bottom: 24, trailing: 20))
                }
            }
        }
    }

    // MARK: Мои сделки

    private var myDealsTab: some View {
        let myFluxId = backend.myFluxId
        let myOffers = backend.p2pOpenOffers.filter {
            $0.creatorFluxId.uppercased() == myFluxId.uppercased()
        }
        let deals = backend.myP2pDeals

        return Group {
            if myOffers.isEmpty && deals.isEmpty {
                Text("У вас пока нет сделок и активных лотов")
                    .font(.system(size: 14))
                    .foregroundStyle(FluxColors.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(myOffers) { offer in
                            CoinsBotMyOfferCard(offer: offer) { toast = $0 }
                        }
                        ForEach(deals) { deal in
                            CoinsBotDealCard(
                                deal: deal,
                                isSeller: deal.sellerFluxId.uppercased() == myFluxId.uppercased()
                            ) { toast = $0 }
                        }
                    }
                    .padding(EdgeInsets(top: 12, leading: 20, bottom: 24, trailing: 20))
                }
            }
        }
    }
}

struct CoinsBotCreateOfferSheet: View {
    @EnvironmentObject var backend: LocalBackend
    @Environment(\.dismiss) private var dismiss

    /// Success toast routed to the P2P sheet underneath (shown after the
    /// dismiss animation).
    let onToast: (Toast) -> Void

    @State private var amountText = ""
    @State private var noteText = ""
    @State private var busy = false
    /// Errors are shown inside this nested sheet while it stays open.
    @State private var toast: Toast?

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            CoinsBotSheetHeader(
                emoji: "🏷",
                title: "Продажа Flux Coins",
                subtitle: "Монеты блокируются на балансе сразу при создании лота"
            )
            VStack(spacing: 0) {
                FluxTextField(text: $amountText, hint: "Количество монет", keyboard: .numberPad)
                FluxTextField(text: $noteText, hint: "Условия / способ оплаты (необязательно)")
                    .padding(.top, 10)
                CoinsBotPrimaryButton(title: "Выставить на продажу", busy: busy, action: create)
                    .padding(.top, 14)
            }
            .padding(EdgeInsets(top: 6, leading: 20, bottom: 0, trailing: 20))
            Spacer(minLength: 16)
        }
        .background(FluxColors.background.ignoresSafeArea())
        .fluxToast($toast)
    }

    private func create() {
        guard let coins = Int(amountText.trimmingCharacters(in: .whitespaces)), coins > 0 else {
            toast = Toast(text: "Введите количество", isError: true)
            return
        }
        busy = true
        Task {
            do {
                _ = try await backend.createP2pSellOffer(
                    coinAmount: coins,
                    priceNote: noteText.trimmingCharacters(in: .whitespaces)
                )
                dismiss()
                // Give the sheet a beat to dismiss before showing the toast
                // on the P2P sheet underneath.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onToast(Toast(text: "Лот создан, монеты заблокированы"))
                }
            } catch {
                busy = false
                toast = Toast(text: error.localizedDescription, isError: true)
            }
        }
    }
}

struct CoinsBotOfferCard: View {
    @EnvironmentObject var backend: LocalBackend

    let offer: FluxP2pOffer
    let onToast: (Toast) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(offer.coinAmount) 🪙")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(FluxColors.textPrimary)
                Spacer()
                Text("Продавец: \(offer.creatorFluxId)")
                    .font(.system(size: 12))
                    .foregroundStyle(FluxColors.textTertiary)
            }
            if !offer.priceNote.isEmpty {
                Text(offer.priceNote)
                    .font(.system(size: 13.5))
                    .foregroundStyle(FluxColors.textSecondary)
                    .padding(.top, 6)
            }
            Button {
                Task {
                    do {
                        _ = try await backend.acceptP2pOffer(offer.id)
                        onToast(Toast(text: "Сделка создана. Монеты заблокированы до подтверждения."))
                    } catch {
                        onToast(Toast(text: error.localizedDescription, isError: true))
                    }
                }
            } label: {
                Text("Принять")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(FluxColors.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(FluxColors.blueSoft)
                    )
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.96))
            .padding(.top, 10)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FluxColors.surfaceGray)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(FluxColors.separator, lineWidth: 1)
        )
    }
}

struct CoinsBotMyOfferCard: View {
    @EnvironmentObject var backend: LocalBackend

    let offer: FluxP2pOffer
    let onToast: (Toast) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(offer.coinAmount) 🪙")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(FluxColors.textPrimary)
                Spacer()
                Text("Ваш лот · escrow")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FluxColors.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(FluxColors.warning.opacity(0.12))
                    )
            }
            Button {
                Task {
                    do {
                        try await backend.cancelP2p(offer.id)
                        onToast(Toast(text: "Лот снят, монеты возвращены"))
                    } catch {
                        onToast(Toast(text: error.localizedDescription, isError: true))
                    }
                }
            } label: {
                Text("Снять с продажи")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(FluxColors.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(FluxColors.danger.opacity(0.10))
                    )
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.96))
            .padding(.top, 10)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FluxColors.surfaceGray)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(FluxColors.warning.opacity(0.35), lineWidth: 1)
        )
    }
}

struct CoinsBotDealCard: View {
    @EnvironmentObject var backend: LocalBackend

    let deal: FluxP2pDeal
    let isSeller: Bool
    let onToast: (Toast) -> Void

    private var statusColor: Color {
        switch deal.status {
        case .escrow: return FluxColors.warning
        case .completed: return FluxColors.online
        case .cancelled: return FluxColors.danger
        case .disputed: return FluxColors.danger
        }
    }

    var body: some View {
        let counterpart = isSeller ? deal.buyerFluxId : deal.sellerFluxId

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(deal.coinAmount) 🪙")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(FluxColors.textPrimary)
                Spacer()
                Text(deal.status.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(statusColor.opacity(0.12))
                    )
            }
            Text("\(isSeller ? "Покупатель" : "Продавец"): \(counterpart)")
                .font(.system(size: 13))
                .foregroundStyle(FluxColors.textSecondary)
                .padding(.top, 6)
            Text("Сделка: \(deal.id)")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(FluxColors.textTertiary)
                .lineLimit(1)

            if deal.status == .escrow {
                HStack(spacing: 8) {
                    if isSeller {
                        dealButton(label: "Подтвердить оплату", color: FluxColors.online) {
                            Task {
                                do {
                                    _ = try await backend.confirmP2pDeal(deal.id)
                                    onToast(Toast(text: "Сделка завершена, монеты переданы покупателю"))
                                } catch {
                                    onToast(Toast(text: error.localizedDescription, isError: true))
                                }
                            }
                        }
                    } else {
                        dealButton(label: "Открыть спор", color: FluxColors.danger) {
                            Task {
                                do {
                                    _ = try await backend.disputeP2pDeal(deal.id)
                                    onToast(Toast(text: "Спор открыт. Монеты останутся заблокированными до решения."))
                                } catch {
                                    onToast(Toast(text: error.localizedDescription, isError: true))
                                }
                            }
                        }
                    }
                    dealButton(label: "Отменить", color: FluxColors.textSecondary) {
                        Task {
                            do {
                                try await backend.cancelP2p(deal.id)
                                onToast(Toast(text: "Сделка отменена, монеты возвращены продавцу"))
                            } catch {
                                onToast(Toast(text: error.localizedDescription, isError: true))
                            }
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FluxColors.surfaceGray)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(FluxColors.separator, lineWidth: 1)
        )
    }

    private func dealButton(label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(color.opacity(0.10))
                )
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.96))
    }
}

// MARK: - 💰 Баланс

struct CoinsBotBalanceSheet: View {
    @EnvironmentObject var backend: LocalBackend

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            CoinsBotSheetHeader(
                emoji: "💰",
                title: "Баланс Flux Coins",
                subtitle: "Единый баланс для Android и iOS"
            )
            Text("\(backend.fluxCoins)")
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(FluxColors.warning)
                .padding(.top, 6)
            Text(
                "Баланс хранится на общем сервере Flux. Клиент не может "
                + "изменить его напрямую — каждая операция проходит "
                + "атомарную проверку и получает уникальный Transaction ID."
            )
            .font(.system(size: 13))
            .lineSpacing(3)
            .foregroundStyle(FluxColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FluxColors.surfaceGray)
            )
            .padding(EdgeInsets(top: 12, leading: 20, bottom: 24, trailing: 20))
        }
        .background(FluxColors.background.ignoresSafeArea())
    }
}

// MARK: - 🛡 Безопасность

struct CoinsBotSecuritySheet: View {
    private static let points: [(String, String)] = [
        ("🔒", "Все операции выполняются на backend — клиент не меняет баланс."),
        ("🧾", "Каждая операция получает уникальный Transaction ID."),
        ("🛡", "Защита от двойной траты, повторного погашения чеков и race conditions."),
        ("⚖️", "Escrow: монеты блокируются до завершения P2P-сделки."),
        ("⏱", "Чеки одноразовые и могут иметь срок действия и получателя."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(FluxColors.separator).frame(width: 40, height: 4).padding(.top, 10)
            CoinsBotSheetHeader(
                emoji: "🛡",
                title: "Безопасность",
                subtitle: "Как защищены операции FluxCoinsBot"
            )
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(Self.points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .top, spacing: 10) {
                        Text(point.0)
                            .font(.system(size: 18))
                        Text(point.1)
                            .font(.system(size: 13.5))
                            .lineSpacing(2)
                            .foregroundStyle(FluxColors.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 6, leading: 20, bottom: 24, trailing: 20))
        }
        .background(FluxColors.background.ignoresSafeArea())
    }
}
