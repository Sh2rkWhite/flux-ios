import SwiftUI

/// Three-page intro shown on first launch only.
struct OnboardingView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    @State private var page = 0

    private struct Page {
        let icon: String
        let gradient: [Color]
        let title: String
        let text: String
    }

    private var pages: [Page] {
        [
            Page(icon: "bubble.left.and.bubble.right.fill",
                 gradient: [Color(hex: 0x4E9BFF), Color(hex: 0x4AC8F0)],
                 title: l10n.obTitle1, text: l10n.obText1),
            Page(icon: "shield.lefthalf.filled",
                 gradient: [Color(hex: 0x8A5CFF), Color(hex: 0x4E9BFF)],
                 title: l10n.obTitle2, text: l10n.obText2),
            Page(icon: "sparkles",
                 gradient: [Color(hex: 0x7C4DFF), Color(hex: 0xC05CFF)],
                 title: l10n.obTitle3, text: l10n.obText3),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            FluxLogoMark(size: 68, animate: true)

            TabView(selection: $page) {
                ForEach(0..<3, id: \.self) { index in
                    let page = pages[index]
                    VStack(spacing: 44) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: page.gradient,
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .frame(width: 168, height: 168)
                                .shadow(color: page.gradient[0].opacity(0.35), radius: 44, y: 18)
                            Image(systemName: page.icon)
                                .font(.system(size: 68))
                                .foregroundStyle(.white)
                        }
                        VStack(spacing: 12) {
                            Text(page.title)
                                .font(.system(size: 26, weight: .heavy))
                                .foregroundStyle(FluxColors.textPrimary)
                                .multilineTextAlignment(.center)
                            Text(page.text)
                                .font(.system(size: 16))
                                .foregroundStyle(FluxColors.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, 40)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: page) { _ in Haptics.selection() }

            FluxPageIndicator(count: 3, index: $page)
                .padding(.top, 24)

            FluxButton(title: page == 2 ? l10n.obStart : "Далее") {
                if page < 2 {
                    withAnimation(FluxMotion.slowDecelAnimation) {
                        page += 1
                    }
                } else {
                    Haptics.medium()
                    Task { await backend.setOnboarded() }
                }
            }
            .padding(EdgeInsets(top: 32, leading: 28, bottom: 28, trailing: 28))
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(FluxColors.background.ignoresSafeArea())
    }
}
