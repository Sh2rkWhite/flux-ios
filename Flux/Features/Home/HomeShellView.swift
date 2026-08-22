import SwiftUI

/// Route destinations shared by all tab navigation stacks.
enum Route: Hashable {
    case chat(chatId: String)
    case userProfile(userId: String)
    case editProfile
    case settings
    case privacy
    case devices
    case levelActivity
    case fluxCoins
    case badgeShop
    case marketplace
    case myQR
    case scanQR
    case adminPanel
    case inCall(peerId: String, video: Bool)
}

/// Main messenger shell — three tabs with a floating pill navigation bar
/// (mirrors the Android HomeShell).
struct HomeShellView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    @State private var tabIndex = 0

    private var totalUnread: Int {
        backend.chats.reduce(0) { $0 + $1.unreadCount }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tabIndex {
                case 0: chatsTab
                case 1: callsTab
                default: ProfileTabView()
                }
            }
            .padding(.bottom, 84)

            navBar
        }
        .background(FluxColors.background.ignoresSafeArea())
    }

    private var chatsTab: some View {
        NavigationStack {
            ChatListView()
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                }
        }
    }

    private var callsTab: some View {
        NavigationStack {
            CallsView()
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                }
        }
    }

    private var navBar: some View {
        HStack(spacing: 0) {
            navSegment(icon: "bubble.left.and.bubble.right.fill", label: l10n.tabChats, index: 0, badge: totalUnread)
            navSegment(icon: "phone.fill", label: l10n.tabCalls, index: 1, badge: 0)
            navSegment(icon: "person.fill", label: l10n.tabProfile, index: 2, badge: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(FluxColors.surface.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(FluxColors.separator, lineWidth: 1)
                )
                .shadow(color: Color(hex: 0x1A2340).opacity(0.1), radius: 24, y: 8)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .frame(maxWidth: 420)
    }

    private func navSegment(icon: String, label: String, index: Int, badge: Int) -> some View {
        Button {
            Haptics.selection()
            withAnimation(FluxMotion.springAnimation) {
                tabIndex = index
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .scaleEffect(tabIndex == index ? 1.08 : 1)
                if tabIndex == index {
                    Text(label)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(tabIndex == index ? FluxColors.blue : FluxColors.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(tabIndex == index ? FluxColors.blueSoft : .clear)
            )
            .overlay(alignment: .topTrailing) {
                if index == 0, badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18)
                        .frame(height: 16)
                        .background(Capsule().fill(FluxColors.gradient))
                        .overlay(Capsule().strokeBorder(FluxColors.background, lineWidth: 1.5))
                        .offset(x: 10, y: -10)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Maps a [Route] to its destination view.
struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .chat(let chatId):
            ChatView(chatId: chatId)
        case .userProfile(let userId):
            UserProfileView(userId: userId)
        case .editProfile:
            ProfileEditView()
        case .settings:
            SettingsView()
        case .privacy:
            PrivacyView()
        case .devices:
            DevicesView()
        case .levelActivity:
            LevelActivityView()
        case .fluxCoins:
            FluxCoinsView()
        case .badgeShop:
            BadgeShopView()
        case .marketplace:
            MarketplaceView()
        case .myQR:
            MyQRView()
        case .scanQR:
            QRScannerView()
        case .adminPanel:
            AdminPanelView()
        case .inCall(let peerId, let video):
            InCallView(peerId: peerId, video: video)
        }
    }
}
