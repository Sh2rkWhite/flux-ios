import SwiftUI

// MARK: - Press-scale button style (the Flux "no ripple" feel)

struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - FluxButton (primary CTA)

struct FluxButton: View {
    let title: String
    var enabled: Bool = true
    var showsProgress: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            guard enabled, !showsProgress else { return }
            Haptics.light()
            action()
        } label: {
            Group {
                if showsProgress {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Group {
                    if enabled {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(FluxColors.gradient)
                            .shadow(color: FluxColors.blue.opacity(0.32), radius: 18, y: 8)
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(FluxColors.separator)
                    }
                }
            )
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.96))
        .disabled(!enabled || showsProgress)
        .animation(FluxMotion.decelAnimation, value: enabled)
    }
}

// MARK: - FluxCircleButton

struct FluxCircleButton: View {
    let systemImage: String
    var size: CGFloat = 40
    var gradientFill = false
    var iconColor: Color = FluxColors.textSecondary
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(gradientFill ? AnyShapeStyle(FluxColors.gradient) : AnyShapeStyle(FluxColors.surfaceGray))
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.52, weight: .medium))
                    .foregroundStyle(gradientFill ? Color.white : iconColor)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.9))
    }
}

// MARK: - FluxCard

/// Rounded surface card; `content` is laid out inside.
struct FluxCard<Content: View>: View {
    var onTap: (() -> Void)? = nil
    var cornerRadius: CGFloat = 24
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if let onTap {
                Button {
                    Haptics.light()
                    onTap()
                } label: {
                    cardBody
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.98))
            } else {
                cardBody
            }
        }
    }

    private var cardBody: some View {
        content()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(FluxColors.surface)
                    .shadow(color: Color(hex: 0x1A2340).opacity(0.04), radius: 16, y: 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(FluxColors.separator.opacity(0.6), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Section title

struct FluxSectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(FluxColors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 20, leading: 24, bottom: 8, trailing: 24))
    }
}

// MARK: - Settings tile

struct FluxSettingsTile<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconColor: Color = FluxColors.blue
    var iconBackground: Color = FluxColors.blueSoft
    var showDivider = false
    var onTap: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        iconColor: Color = FluxColors.blue,
        iconBackground: Color = FluxColors.blueSoft,
        showDivider: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        onTap: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.iconColor = iconColor
        self.iconBackground = iconBackground
        self.showDivider = showDivider
        self.trailing = trailing
        self.onTap = onTap
    }

    var body: some View {
        Group {
            if let onTap {
                tileContent
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Haptics.light()
                        onTap()
                    }
            } else {
                // No tap handler: keep the row inert so the enclosing
                // Button / NavigationLink receives the tap instead of a
                // no-op gesture stealing it.
                tileContent
            }
        }
    }

    private var tileContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconBackground)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(iconColor)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(FluxColors.textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(FluxColors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
            if showDivider {
                Divider()
                    .overlay(FluxColors.separator)
                    .padding(.leading, 66)
            }
        }
    }
}

// MARK: - Switch

struct FluxSwitch: View {
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            Haptics.selection()
            onChange(!isOn)
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(FluxColors.gradient) : AnyShapeStyle(Color(hex: 0xE8EAF0)))
                    .frame(width: 52, height: 32)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    .frame(width: 26, height: 26)
                    .padding(3)
            }
            .animation(FluxMotion.springAnimation, value: isOn)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Text field

struct FluxTextField: View {
    @Binding var text: String
    var hint: String = ""
    var obscure = false
    var keyboard: KeyboardType = .default
    var autofocus = false
    var maxLength: Int? = nil
    var onSubmitted: (() -> Void)? = nil

    enum KeyboardType {
        case `default`, email, numberPad
    }

    @FocusState private var focused: Bool

    var body: some View {
        TextField(hint, text: $text)
            .keyboardType(keyboard == .email ? .emailAddress : (keyboard == .numberPad ? .numberPad : .default))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($focused)
            .foregroundStyle(FluxColors.textPrimary)
            .font(.system(size: 17, weight: .medium))
            .onSubmit { onSubmitted?() }
            .onChange(of: text) { newValue in
                if let maxLength, newValue.count > maxLength {
                    text = String(newValue.prefix(maxLength))
                }
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(FluxColors.surfaceGray)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(focused ? FluxColors.blue : .clear, lineWidth: 1.5)
            )
            .textContentType(obscure ? .password : .none)
            .privacySensitive(obscure)
            .onAppear {
                if autofocus {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        focused = true
                    }
                }
            }
    }
}

// MARK: - Search field

struct FluxSearchField: View {
    @Binding var text: String
    let hint: String
    var autofocus = false

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19))
                .foregroundStyle(FluxColors.textTertiary)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(hint)
                        .font(.system(size: 15.5))
                        .foregroundStyle(FluxColors.textTertiary)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .font(.system(size: 15.5))
                    .foregroundStyle(FluxColors.textPrimary)
                    .focused($focused)
                    .submitLabel(.search)
            }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(FluxColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FluxColors.surface)
                .shadow(color: Color(hex: 0x1A2340).opacity(0.03), radius: 10, y: 3)
        )
        .onAppear {
            if autofocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    focused = true
                }
            }
        }
    }
}

// MARK: - Empty state

struct FluxEmptyState: View {
    let icon: String
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(FluxColors.blueSoft)
                .frame(width: 92, height: 92)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 38))
                        .foregroundStyle(FluxColors.blue)
                )
                .padding(.bottom, 20)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(FluxColors.textPrimary)
                .padding(.bottom, 6)
            Text(hint)
                .font(.system(size: 14.5))
                .foregroundStyle(FluxColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Logo mark

struct FluxLogoMark: View {
    var size: CGFloat = 56
    var animate = false

    @State private var breathing = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(FluxColors.gradient)
            .frame(width: size, height: size)
            .shadow(color: FluxColors.violet.opacity(0.35), radius: size * 0.22, y: size * 0.12)
            .overlay(
                Text("f")
                    .font(.system(size: size * 0.56, weight: .bold))
                    .foregroundStyle(.white)
            )
            .scaleEffect(breathing ? 1.04 : 0.96)
            .onAppear {
                if animate {
                    withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                        breathing = true
                    }
                }
            }
    }
}

// MARK: - Page indicator

struct FluxPageIndicator: View {
    let count: Int
    @Binding var index: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? AnyShapeStyle(FluxColors.gradient) : AnyShapeStyle(FluxColors.separator))
                    .frame(width: i == index ? 24 : 8, height: 8)
                    .animation(FluxMotion.decelAnimation, value: index)
            }
        }
    }
}

// MARK: - Avatar

/// Flux avatar: photo, or a gradient circle with initials. Optionally
/// shows the online indicator.
struct FluxAvatarView: View {
    let user: FluxUser?
    var size: CGFloat = 52
    var showOnline = false
    var onlineOverride: Bool? = nil

    private var image: UIImage? {
        guard let path = user?.avatarPath else { return nil }
        return UIImage(contentsOfFile: path)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(FluxColors.avatarGradient(user?.fluxId ?? user?.id ?? "flux"))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(user?.isSupport == true ? "💙" : initialsOf(user?.name ?? "F"))
                    .font(.system(size: user?.isSupport == true ? size * 0.42 : size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if showOnline, (onlineOverride ?? user?.isOnline ?? false) {
                Circle()
                    .fill(FluxColors.online)
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(
                        Circle()
                            .stroke(FluxColors.background, lineWidth: size * 0.045)
                    )
            }
        }
    }
}

// MARK: - Banner

/// Profile banner: photo, or a deterministic gradient with a scrim.
struct FluxBannerView: View {
    let user: FluxUser?
    var bannerPath: String?
    var height: CGFloat = 200

    private var image: UIImage? {
        guard let bannerPath else { return nil }
        return UIImage(contentsOfFile: bannerPath)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(FluxColors.bannerGradient(user?.fluxId ?? "flux"))
            }
            LinearGradient(
                colors: [.clear, .black.opacity(0.35)],
                startPoint: .top, endPoint: .bottom)
                .frame(height: 80)
        }
        .frame(height: height)
        .clipped()
    }
}

// MARK: - Level badge

struct LevelBadgeView: View {
    let level: Int
    var size: CGFloat = 36

    private var tier: LevelTier { levelTier(level) }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: tier.gradient,
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: tier.gradient[0].opacity(0.4), radius: 8, y: 3)
            Text("\(level)")
                .font(.system(size: size * 0.3, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Snackbars / toasts

struct Toast: Equatable {
    let text: String
    var isError = false
}

struct ToastOverlay: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                Text(toast.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(toast.isError ? FluxColors.danger : .white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(toast.isError ? FluxColors.danger.opacity(0.12) : Color(hex: 0x12141C).opacity(0.92))
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        withAnimation(FluxMotion.decelAnimation) {
                            self.toast = nil
                        }
                    }
            }
        }
        .animation(FluxMotion.decelAnimation, value: toast)
    }
}

extension View {
    func fluxToast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastOverlay(toast: toast))
    }
}
