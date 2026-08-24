import SwiftUI

/// Full conversation screen: grouping, day dividers, receipts, reply/edit,
/// reactions, media, voice, typing indicator and the level-up overlay.
struct ChatView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n
    @Environment(\.dismiss) private var dismiss

    let chatId: String

    @State private var replyTarget: FluxMessage?
    @State private var editTarget: FluxMessage?
    @State private var actionTarget: FluxMessage?
    @State private var forwardTarget: FluxMessage?
    @State private var attachmentSheet = false
    @State private var showGallery = false
    @State private var showCamera = false
    @State private var showFilePicker = false
    @State private var toast: Toast?
    @State private var levelUp: (level: Int, badges: [FluxBadge])?
    @State private var lastKnownLevel: Int?
    /// One-time guard for the «Support AI unavailable» system notice.
    @State private var supportUnavailableNotified = false
    /// Programmatic push targets resolved by `openPeerProfile()`.
    @State private var pushProfileUserId: String?
    @State private var pushCoinsBot = false

    @StateObject private var recorder = VoiceRecorder()
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared

    private var chat: FluxChat? {
        backend.chatStorage[chatId]
    }

    private var peer: FluxUser? {
        chat.flatMap { backend.userById($0.peerId) }
    }

    private var messages: [FluxMessage] {
        backend.messagesOf(chatId)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(FluxColors.separator)
            messageList
            if backend.me?.isFrozen == true {
                frozenBanner
            } else if peer?.isCoinsBot == true {
                coinsBotOpenBar
            } else if recorder.recording {
                RecordingBar(recorder: recorder) { send in
                    if let result = recorder.stop(send: send), !result.0.isEmpty {
                        Task {
                            _ = await backend.sendVoice(chatId, result.0, result.1)
                            checkLevelUp()
                        }
                    }
                }
            } else {
                ChatInputBar(
                    onSend: { text in
                        Task {
                            if let editTarget {
                                await backend.editMessage(editTarget.id, text)
                                self.editTarget = nil
                            } else {
                                _ = await backend.sendText(chatId, text, replyToId: replyTarget?.id)
                                replyTarget = nil
                                await maybeSupportAiReply()
                            }
                            checkLevelUp()
                        }
                    },
                    onAttach: { attachmentSheet = true },
                    onMicTap: {
                        Task { _ = await recorder.start() }
                    },
                    replyTarget: $replyTarget,
                    editTarget: $editTarget
                )
            }
        }
        .background(FluxColors.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .fluxToast($toast)
        .sheet(isPresented: $attachmentSheet) { attachmentSheetContent }
        .sheet(isPresented: $showGallery) {
            PhotoLibraryPicker { data in
                if let path = FluxMediaStore.saveImage(data, prefix: "img") {
                    Task { _ = await backend.sendImage(chatId, path, replyToId: replyTarget?.id) }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                if let path = FluxMediaStore.saveImage(data, prefix: "cam") {
                    Task { _ = await backend.sendImage(chatId, path, replyToId: replyTarget?.id) }
                }
            }
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker { url in
                if let saved = FluxMediaStore.saveFile(at: url, preferredName: nil) {
                    Task { _ = await backend.sendFile(chatId, saved.path, saved.name, saved.size, replyToId: replyTarget?.id) }
                }
            }
        }
        .sheet(item: $actionTarget) { message in
            MessageActionSheet(
                message: message,
                isMine: message.senderId == (backend.me?.id ?? "me"),
                onReact: { emoji in
                    Task {
                        await backend.toggleReaction(message.id, emoji, backend.me?.id ?? "me")
                    }
                },
                onReply: {
                    replyTarget = message
                    editTarget = nil
                },
                onEdit: {
                    editTarget = message
                    replyTarget = nil
                },
                onCopy: {
                    UIPasteboard.general.string = message.text
                    Haptics.selection()
                },
                onForward: {
                    if backend.privacy.forbidForward {
                        toast = Toast(text: l10n.forwardDisabled, isError: true)
                    } else {
                        forwardTarget = message
                    }
                },
                onDelete: {
                    Task { await backend.deleteMessage(message.id) }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $forwardTarget) { message in
            ForwardSheet(message: message)
                .presentationDetents([.medium])
        }
        .fullScreenCover(item: Binding(
            get: { levelUp.map { LevelUpPayload(level: $0.level, badges: $0.badges) } },
            set: { levelUp = $0.map { (level: $0.level, badges: $0.badges) } }
        )) { payload in
            LevelUpOverlay(payload: payload)
        }
        .onAppear {
            Task { await backend.markChatRead(chatId) }
            lastKnownLevel = backend.myProfile.level
            fetchPeerIfNeeded()
        }
        .onChange(of: chat?.unreadCount) { unread in
            if unread ?? 0 > 0 {
                Task { await backend.markChatRead(chatId) }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { pushCoinsBot },
            set: { pushCoinsBot = $0 }
        )) {
            CoinsBotView()
        }
        .navigationDestination(isPresented: Binding(
            get: { pushProfileUserId != nil },
            set: { if !$0 { pushProfileUserId = nil } }
        )) {
            if let userId = pushProfileUserId {
                UserProfileView(userId: userId)
            }
        }
    }

    private var attachmentSheetContent: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(FluxColors.separator)
                .frame(width: 40, height: 4)
                .padding(.top, 10)
            ForEach(AttachmentKind.allCases) { kind in
                FluxSettingsTile(
                    icon: kind.icon,
                    title: kind.title,
                    iconColor: kind == .gallery ? FluxColors.blue : (kind == .camera ? FluxColors.violet : FluxColors.warning),
                    iconBackground: kind == .gallery ? FluxColors.blueSoft : (kind == .camera ? FluxColors.violetSoft : FluxColors.warning.opacity(0.13)),
                    onTap: {
                        attachmentSheet = false
                        switch kind {
                        case .gallery: showGallery = true
                        case .camera: showCamera = true
                        case .file: showFilePicker = true
                        }
                    }
                )
                .padding(.horizontal, 8)
            }
            Spacer(minLength: 16)
        }
        .frame(minHeight: 260)
        .background(FluxColors.background.ignoresSafeArea())
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: Frozen banner

    private var frozenBanner: some View {
        Text("❄️ Аккаунт заморожен. Доступно только чтение.")
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(FluxColors.warning)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FluxColors.warning.opacity(0.12))
            )
            .padding(12)
    }

    // MARK: Coins bot input replacement

    /// @FluxCoinsBot chat: the composer is replaced by a single CTA that
    /// opens the bot interface (mirrors the Dart chat screen).
    private var coinsBotOpenBar: some View {
        Button {
            Haptics.light()
            pushCoinsBot = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 18))
                Text("Открыть Flux Coins Bot")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(FluxColors.gradient)
                    .shadow(color: FluxColors.blue.opacity(0.32), radius: 18, y: 8)
            )
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.97))
        .padding(12)
    }

    // MARK: Peer resolution

    /// Opens the profile of the chat peer (avatar / name tap). Always targets
    /// the peer's own id — never the local user — and fetches the real user
    /// document on demand when the contact is not cached yet (mirrors the
    /// Dart `_openPeerProfile`).
    private func openPeerProfile() {
        // The only valid target is the chat peer (= sender of incoming
        // messages). The local user's id must never be substituted.
        let targetId = peer?.id ?? chat?.peerId
        guard let targetId, !targetId.isEmpty else { return }
        // @FluxCoinsBot has no profile — taps open the bot interface instead.
        if targetId == FluxUser.coinsBotId {
            Haptics.light()
            pushCoinsBot = true
            return
        }
        let meId = backend.me?.id
        if let meId, targetId == meId { return }

        if let user = peer ?? backend.userById(targetId) {
            // Defensive: a 1:1 chat peer must never resolve to the local user.
            if let meId, user.id == meId { return }
            Haptics.light()
            pushProfileUserId = user.id
            return
        }
        Task {
            let user = await backend.ensureUser(targetId)
            guard let user else {
                toast = Toast(text: "Не удалось загрузить профиль пользователя", isError: true)
                return
            }
            // Defensive: a 1:1 chat peer must never resolve to the local user.
            if let meId, user.id == meId { return }
            Haptics.light()
            pushProfileUserId = user.id
        }
    }

    /// The chat may arrive from the shared backend before the directory pull
    /// finished — fetch the peer contact on demand instead of showing an
    /// empty header.
    private func fetchPeerIfNeeded() {
        guard peer == nil, let peerId = chat?.peerId, !peerId.isEmpty else { return }
        guard peerId != backend.me?.id else { return }
        Task { _ = await backend.ensureUser(peerId) }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(FluxColors.textPrimary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(ScaleButtonStyle())

            Button {
                openPeerProfile()
            } label: {
                peerHeaderContent
            }
            .buttonStyle(.plain)

            Spacer()

            if let peer, !peer.isSupport, !peer.isCoinsBot {
                NavigationLink(value: Route.inCall(peerId: peer.id, video: false)) {
                    ZStack {
                        Circle().fill(FluxColors.surfaceGray).frame(width: 40, height: 40)
                        Image(systemName: "phone.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(FluxColors.textSecondary)
                    }
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.9))
                NavigationLink(value: Route.inCall(peerId: peer.id, video: true)) {
                    ZStack {
                        Circle().fill(FluxColors.surfaceGray).frame(width: 40, height: 40)
                        Image(systemName: "video.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(FluxColors.textSecondary)
                    }
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.9))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var peerHeaderContent: some View {
        HStack(spacing: 11) {
            FluxAvatarView(
                user: peer,
                size: 40,
                showOnline: true,
                onlineOverride: backend.privacy.showOnline ? nil : false
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(peer?.name ?? "Flux")
                    .font(.system(size: 16.5, weight: .bold))
                    .foregroundStyle(FluxColors.textPrimary)
                    .lineLimit(1)
                subtitle
            }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if backend.isPeerTyping(chatId) {
            Text(l10n.typing)
                .font(.system(size: 13))
                .foregroundStyle(FluxColors.blue)
        } else if peer?.isSupport == true || peer?.isOnline == true {
            Text(l10n.online)
                .font(.system(size: 13))
                .foregroundStyle(FluxColors.online)
        } else if backend.privacy.showLastSeen, let lastSeen = peer?.lastSeenMs {
            Text(l10n.lastSeenAt(formatTime(lastSeen)))
                .font(.system(size: 13))
                .foregroundStyle(FluxColors.textSecondary)
        } else {
            Text(" ")
                .font(.system(size: 13))
        }
    }

    // MARK: Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { _, item in
                        switch item {
                        case .dayDivider(let ms):
                            DayDividerView(ms: ms)
                                .id("day-\(ms)")
                        case .message(let message, let showTail, let showTopGap):
                            MessageBubbleView(
                                message: message,
                                isMine: message.senderId == (backend.me?.id ?? "me"),
                                showTail: showTail,
                                showTopGap: showTopGap,
                                onLongPress: {
                                    Haptics.medium()
                                    actionTarget = message
                                },
                                replyMessage: replyPreview(for: message)
                            )
                            .id(message.id)
                        }
                    }
                    if backend.isPeerTyping(chatId) {
                        TypingBubble()
                            .padding(.top, 6)
                    }
                    Color.clear.frame(height: 8).id("bottom-anchor")
                }
                .padding(.horizontal, 16)
            }
            .onAppear {
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: messages.count) { _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(animated ? FluxMotion.decelAnimation : nil) {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        }
    }

    // MARK: Grouping

    private enum DisplayItem: Identifiable {
        case dayDivider(ms: Int)
        case message(FluxMessage, showTail: Bool, showTopGap: Bool)

        var id: String {
            switch self {
            case .dayDivider(let ms): return "day-\(ms)"
            case .message(let m, _, _): return m.id
            }
        }
    }

    private var displayItems: [DisplayItem] {
        var items: [DisplayItem] = []
        var previous: FluxMessage?
        for message in messages {
            if previous == nil || !Calendar.current.isDate(
                Date(timeIntervalSince1970: TimeInterval(message.sentAtMs) / 1000),
                inSameDayAs: Date(timeIntervalSince1970: TimeInterval(previous!.sentAtMs) / 1000)) {
                items.append(.dayDivider(ms: message.sentAtMs))
            }
            let newGroup = previous == nil
                || previous!.senderId != message.senderId
                || message.sentAtMs - previous!.sentAtMs > 5 * 60 * 1000
            items.append(.message(message, showTail: newGroup, showTopGap: newGroup))
            previous = message
        }
        return items
    }

    private func replyPreview(for message: FluxMessage) -> FluxMessage? {
        guard let replyId = message.replyToId else { return nil }
        return messages.first { $0.id == replyId }
    }

    // MARK: Level-up

    private func checkLevelUp() {
        let currentLevel = backend.myProfile.level
        if let lastKnownLevel, currentLevel > lastKnownLevel {
            levelUp = (currentLevel, backend.myProfile.badges.filter { ($0.earnedAtMs ?? 0) > Int(Date().timeIntervalSince1970 * 1000) - 10_000 })
            Haptics.success()
        }
        lastKnownLevel = currentLevel
    }

    // MARK: Flux Support AI

    /// Flux Support AI: separate assistant chat with context, typing state
    /// and graceful errors. The API key lives only on the proxy side
    /// (mirrors the Android `_maybeSupportAiReply`).
    private func maybeSupportAiReply() async {
        guard peer?.isSupport == true else { return }

        let history: [[String: String]] = backend.messagesOf(chatId)
            .filter { !$0.isSystemMessage }
            .map { message in
                [
                    "role": message.senderId == FluxUser.supportId ? "assistant" : "user",
                    "content": message.text,
                ]
            }

        backend.setSupportTyping(chatId, true)
        let reply = await SupportAi.ask(history: history)
        backend.setSupportTyping(chatId, false)

        if let reply {
            backend.postSupportReply(chatId, reply)
        } else if !supportUnavailableNotified {
            supportUnavailableNotified = true
            backend.postSupportReply(
                chatId,
                SupportAi.available
                    ? "ИИ-помощник временно недоступен. Опишите проблему — команда Flux ответит вручную."
                    : "Здравствуйте! Я помощник Flux Support. ИИ-модуль сейчас отключён — опишите проблему, и команда Flux ответит вручную.",
                system: true
            )
        }
    }
}

/// Identifiable payload for the level-up full-screen cover.
struct LevelUpPayload: Identifiable {
    let level: Int
    let badges: [FluxBadge]
    var id: Int { level }
}

/// Full-screen LEVEL UP overlay (mirrors the Android LevelUpOverlay).
struct LevelUpOverlay: View {
    let payload: LevelUpPayload
    @Environment(\.dismiss) private var dismiss

    @State private var appear = false

    private var tier: LevelTier { levelTier(payload.level) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [tier.gradient[0].opacity(0.5), tier.gradient[1].opacity(0.15), .clear],
                                center: .center, startRadius: 8, endRadius: 110)
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(appear ? 1.08 : 0.94)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: appear)
                    Circle()
                        .fill(LinearGradient(colors: tier.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 80, height: 80)
                        .shadow(color: tier.gradient[0].opacity(0.5), radius: 20, y: 2)
                        .overlay(
                            Text("\(payload.level)")
                                .font(.system(size: 32, weight: .heavy))
                                .foregroundStyle(.white)
                        )
                }
                Text("LEVEL UP!")
                    .font(.system(size: 32, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(
                        LinearGradient(colors: tier.gradient, startPoint: .leading, endPoint: .trailing)
                    )
                Text("Вы достигли уровня \(payload.level)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: 0x9AA1B5))
                    .multilineTextAlignment(.center)

                if !payload.badges.isEmpty {
                    VStack(spacing: 12) {
                        Divider().overlay(Color(hex: 0x262A38))
                        Text("Новые бейджи")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x6E7488))
                        FlowLayout(spacing: 8) {
                            ForEach(payload.badges) { badge in
                                HStack(spacing: 6) {
                                    Text(badge.emoji)
                                    Text(badge.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(badge.rarity.color)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(badge.rarity.color.opacity(0.12)))
                                .overlay(Capsule().strokeBorder(badge.rarity.color.opacity(0.4), lineWidth: 1))
                            }
                        }
                    }
                }
                Text("Нажмите, чтобы закрыть")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color(hex: 0x0E1016))
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(tier.gradient[0].opacity(0.4), lineWidth: 1.5)
                    )
                    .shadow(color: tier.gradient[0].opacity(0.3), radius: 40, y: 4)
            )
            .padding(.horizontal, 32)
        }
        .onTapGesture { dismiss() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appear = true }
            Task {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                dismiss()
            }
        }
    }
}

/// Simple wrapping layout for badge/gift chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Day divider inside a chat.
struct DayDividerView: View {
    let ms: Int

    var body: some View {
        Text(formatDayDivider(ms))
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(FluxColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(FluxColors.surface)
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

/// The peer's typing indicator bubble.
struct TypingBubble: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(FluxColors.textTertiary)
                    .frame(width: 7, height: 7)
                    .offset(y: phase ? -4 : 2)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18),
                        value: phase
                    )
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(FluxColors.surface)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 56)
        .onAppear { phase = true }
    }
}

/// Message action bottom sheet: quick reactions + actions.
struct MessageActionSheet: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n
    @Environment(\.dismiss) private var dismiss

    let message: FluxMessage
    let isMine: Bool
    let onReact: (String) -> Void
    let onReply: () -> Void
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onForward: () -> Void
    let onDelete: () -> Void

    private static let quickReactions = ["❤️", "👍", "😂", "😮", "😢", "🔥"]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(FluxColors.separator)
                .frame(width: 40, height: 4)
                .padding(.top, 10)

            HStack(spacing: 4) {
                ForEach(Self.quickReactions, id: \.self) { emoji in
                    let reacted = message.reactions[emoji]?.contains(backend.me?.id ?? "me") == true
                    Button {
                        onReact(emoji)
                        dismiss()
                    } label: {
                        Text(emoji)
                            .font(.system(size: 24))
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(reacted ? FluxColors.blueSoft : .clear)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.vertical, 14)

            Divider().overlay(FluxColors.separator)

            VStack(spacing: 0) {
                FluxSettingsTile(icon: "arrowshape.turn.up.left", title: l10n.reply, onTap: {
                    onReply()
                    dismiss()
                })
                if isMine, message.kind == .text {
                    FluxSettingsTile(icon: "pencil", title: l10n.edit, iconColor: FluxColors.violet, iconBackground: FluxColors.violetSoft, onTap: {
                        onEdit()
                        dismiss()
                    })
                }
                if message.kind == .text {
                    FluxSettingsTile(icon: "doc.on.doc", title: l10n.copy, onTap: {
                        onCopy()
                        dismiss()
                    })
                    FluxSettingsTile(icon: "arrowshape.turn.up.right", title: l10n.forward, onTap: {
                        onForward()
                        dismiss()
                    })
                }
                if isMine {
                    FluxSettingsTile(icon: "trash", title: l10n.delete, iconColor: FluxColors.danger, iconBackground: FluxColors.danger.opacity(0.1), onTap: {
                        onDelete()
                        dismiss()
                    })
                }
            }
            .padding(.bottom, 16)
        }
        .background(FluxColors.background.ignoresSafeArea())
    }
}

/// Forward picker sheet.
struct ForwardSheet: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n
    @Environment(\.dismiss) private var dismiss

    let message: FluxMessage

    private var targets: [FluxChat] {
        backend.chats.filter { $0.id != message.chatId }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(FluxColors.separator)
                .frame(width: 40, height: 4)
                .padding(.top, 10)
            Text(l10n.forward)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(FluxColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 18, leading: 20, bottom: 12, trailing: 20))

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(targets) { chat in
                        let peer = backend.userById(chat.peerId)
                        FluxSettingsTile(
                            icon: "person.fill",
                            title: peer?.name ?? "Flux",
                            onTap: {
                                Task {
                                    _ = await backend.sendText(chat.id, message.text)
                                    dismiss()
                                }
                            }
                        )
                        .padding(.horizontal, 8)
                    }
                }
            }
        }
        .background(FluxColors.background.ignoresSafeArea())
    }
}
