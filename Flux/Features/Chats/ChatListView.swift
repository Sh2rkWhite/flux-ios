import SwiftUI

/// Conversations list with search and new-chat entry (tab «Чаты»).
struct ChatListView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    @State private var query = ""
    @State private var showNewChat = false
    @State private var pushChatId: String?

    private var filteredChats: [FluxChat] {
        let all = backend.chats
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { chat in
            let peer = backend.userById(chat.peerId)
            let name = peer?.name ?? "Flux"
            return name.lowercased().contains(q)
                || chat.lastMessagePreview.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filteredChats.isEmpty {
                        FluxEmptyState(
                            icon: "bubble.left.and.bubble.right",
                            title: l10n.noChatsYet,
                            hint: l10n.noChatsHint
                        )
                        .padding(.top, 80)
                    } else {
                        ForEach(Array(filteredChats.enumerated()), id: \.element.id) { index, chat in
                            ChatTileView(chat: chat)
                                .padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
                        }
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 4, bottom: 110, trailing: 4))
            }
        }
        .background(FluxColors.background.ignoresSafeArea())
        .sheet(isPresented: $showNewChat) {
            NewChatSheet { openedChatId in
                pushChatId = openedChatId
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { pushChatId != nil },
            set: { if !$0 { pushChatId = nil } }
        )) {
            if let chatId = pushChatId {
                ChatView(chatId: chatId)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                Text("Flux")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(FluxColors.gradient)
                Spacer()
                FluxCircleButton(systemImage: "square.and.pencil", size: 42, gradientFill: true) {
                    showNewChat = true
                }
            }
            FluxSearchField(text: $query, hint: l10n.searchChats)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 0, trailing: 20))
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }
}

/// A single conversation tile.
struct ChatTileView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    let chat: FluxChat

    private var peer: FluxUser? {
        backend.userById(chat.peerId)
    }

    var body: some View {
        NavigationLink(value: Route.chat(chatId: chat.id)) {
            rowContent
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.98))
        .simultaneousGesture(TapGesture().onEnded {
            Task { await backend.markChatRead(chat.id) }
        })
        .contextMenu {
            Button {
                Task { await backend.toggleChatPin(chat.id) }
            } label: {
                Label(chat.pinned ? l10n.unpin : l10n.pin, systemImage: "pin")
            }
            Button(role: .destructive) {
                Task { await backend.deleteChat(chat.id) }
            } label: {
                Label(l10n.delete, systemImage: "trash")
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 13) {
            FluxAvatarView(
                user: peer,
                size: 54,
                showOnline: true,
                onlineOverride: backend.privacy.showOnline ? nil : false
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(peer?.name ?? "Flux")
                        .font(.system(size: 16.5, weight: peer?.isSupport == true ? .bold : .semibold))
                        .foregroundStyle(FluxColors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if chat.lastMessageAtMs > 0 {
                        Text(formatChatTime(chat.lastMessageAtMs))
                            .font(.system(size: 12.5))
                            .foregroundStyle(FluxColors.textTertiary)
                    }
                }
                HStack {
                    if chat.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(FluxColors.textTertiary)
                    }
                    if backend.isPeerTyping(chat.id) {
                        Text(l10n.typing)
                            .font(.system(size: 14))
                            .foregroundStyle(FluxColors.blue)
                            .lineLimit(1)
                    } else if !chat.lastMessagePreview.isEmpty {
                        Text(chat.lastMessagePreview)
                            .font(.system(size: 14))
                            .foregroundStyle(FluxColors.textSecondary)
                            .lineLimit(1)
                    } else if peer?.isSupport == true {
                        Text(l10n.supportGreeting)
                            .font(.system(size: 14).italic())
                            .foregroundStyle(FluxColors.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Capsule().fill(FluxColors.gradient))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FluxColors.surface)
                .shadow(color: Color(hex: 0x1A2340).opacity(0.04), radius: 12, y: 4)
        )
    }
}

/// New-chat sheet: local directory search, remote @username lookup and
/// add-by-FluxID.
struct NewChatSheet: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    private let onOpenChat: (String) -> Void

    init(onOpenChat: @escaping (String) -> Void) {
        self.onOpenChat = onOpenChat
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var localResults: [FluxUser] {
        backend.searchUsers(trimmedQuery)
    }

    private var looksLikeFluxId: Bool {
        let q = trimmedQuery.uppercased()
        return q.hasPrefix("FLX-") || (q.hasPrefix("FLX") && q.count >= 9)
    }

    private var showUsernameLookup: Bool {
        trimmedQuery.hasPrefix("@") && trimmedQuery.count >= 2 && localResults.isEmpty
    }

    private var showFluxIdLookup: Bool {
        looksLikeFluxId
            && !localResults.contains { $0.fluxId.uppercased() == trimmedQuery.uppercased() }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Capsule()
                    .fill(FluxColors.separator)
                    .frame(width: 40, height: 4)
                    .padding(.top, 10)

                Text(l10n.newChat)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(FluxColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20))

                FluxSearchField(text: $query, hint: "Поиск по @username или FluxID", autofocus: true)
                    .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 0) {
                        if showUsernameLookup {
                            lookupCard(
                                icon: "person.crop.circle.badge.at",
                                title: trimmedQuery,
                                subtitle: "Найти пользователя"
                            ) {
                                Task {
                                    if let found = await backend.lookupUsername(trimmedQuery) {
                                        await openChat(found)
                                    }
                                }
                            }
                        }
                        if showFluxIdLookup {
                            lookupCard(
                                icon: "person.badge.plus",
                                title: trimmedQuery.uppercased(),
                                subtitle: l10n.searchById
                            ) {
                                let user = backend.registerExternalUser(trimmedQuery)
                                Task { await openChat(user) }
                            }
                        }

                        Text(l10n.contacts.uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(FluxColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(EdgeInsets(top: 14, leading: 6, bottom: 8, trailing: 6))

                        if localResults.isEmpty {
                            Text(l10n.noResults)
                                .font(.system(size: 14.5))
                                .foregroundStyle(FluxColors.textSecondary)
                                .padding(.top, 28)
                        } else {
                            ForEach(localResults) { user in
                                ContactRow(user: user)
                                    .padding(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                                    .onTapGesture {
                                        Haptics.light()
                                        Task { await openChat(user) }
                                    }
                            }
                        }
                    }
                    .padding(EdgeInsets(top: 10, leading: 16, bottom: 24, trailing: 16))
                }
            }
            .background(FluxColors.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.hidden)
    }

    private func lookupCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            HStack(spacing: 13) {
                Circle()
                    .fill(FluxColors.gradient)
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 19))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(FluxColors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(FluxColors.textSecondary)
                }
                Spacer()
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FluxColors.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(FluxColors.surface)
            )
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.98))
        .padding(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
    }

    private func openChat(_ user: FluxUser) async {
        let chat = await backend.openChatWithUser(user)
        dismiss()
        // Give the sheet a beat to dismiss before pushing the chat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onOpenChat(chat.id)
        }
    }
}

/// A directory contact row.
struct ContactRow: View {
    @EnvironmentObject var backend: LocalBackend

    let user: FluxUser

    var body: some View {
        HStack(spacing: 13) {
            FluxAvatarView(
                user: user,
                size: 46,
                showOnline: true,
                onlineOverride: backend.privacy.showOnline ? nil : false
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.name)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(FluxColors.textPrimary)
                        .lineLimit(1)
                    if user.isPremium {
                        Text("★")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(FluxColors.gradient))
                    }
                }
                Text(user.username != nil ? "@\(user.username!) · \(user.fluxId)" : user.fluxId)
                    .font(.system(size: 13))
                    .tracking(0.4)
                    .foregroundStyle(FluxColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FluxColors.surface)
        )
    }
}
