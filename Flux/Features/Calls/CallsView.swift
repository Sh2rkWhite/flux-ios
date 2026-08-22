import SwiftUI

/// Call history (tab «Вызовы»).
struct CallsView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    var body: some View {
        VStack(spacing: 0) {
            Text(l10n.tabCalls)
                .font(.system(size: 28, weight: .heavy))
                .tracking(-0.7)
                .foregroundStyle(FluxColors.textPrimary)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 20, leading: 24, bottom: 8, trailing: 24))

            ScrollView {
                LazyVStack(spacing: 0) {
                    if backend.calls.isEmpty {
                        FluxEmptyState(
                            icon: "phone",
                            title: l10n.noCalls,
                            hint: l10n.noCallsHint
                        )
                        .padding(.top, 80)
                    } else {
                        ForEach(backend.calls) { call in
                            CallTileView(call: call)
                                .padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
                        }
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 4, bottom: 110, trailing: 4))
            }
        }
        .background(FluxColors.background.ignoresSafeArea())
    }
}

private struct CallTileView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    let call: CallRecord

    private var peer: FluxUser? {
        backend.userById(call.peerId)
    }

    private var directionIcon: String {
        switch call.direction {
        case .outgoing: return "arrow.up.right"
        case .incoming: return "arrow.down.left"
        case .missed: return "arrow.down.left"
        }
    }

    private var directionColor: Color {
        switch call.direction {
        case .outgoing: return FluxColors.blue
        case .incoming: return FluxColors.online
        case .missed: return FluxColors.danger
        }
    }

    var body: some View {
        NavigationLink(value: Route.inCall(peerId: call.peerId, video: call.type == .video)) {
            HStack(spacing: 13) {
                FluxAvatarView(user: peer, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(peer?.name ?? "Flux")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FluxColors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: directionIcon)
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(directionLabel) · \(call.type == .audio ? l10n.audioCall : l10n.videoCall)")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(call.direction == .missed ? FluxColors.danger : FluxColors.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCallTime(call.atMs))
                        .font(.system(size: 12.5))
                        .foregroundStyle(FluxColors.textTertiary)
                    if call.durationSec > 0 {
                        Text(formatDurationMs(call.durationSec * 1000))
                            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(FluxColors.textSecondary)
                    }
                }
                ZStack {
                    Circle().fill(FluxColors.blueSoft)
                    Image(systemName: call.type == .audio ? "phone.fill" : "video.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(FluxColors.blue)
                }
                .frame(width: 38, height: 38)
            }
            .padding(EdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12))
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(FluxColors.surface)
                    .shadow(color: Color(hex: 0x1A2340).opacity(0.04), radius: 12, y: 4)
            )
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.98))
        .simultaneousGesture(TapGesture().onEnded { Haptics.medium() })
    }

    private var directionLabel: String {
        switch call.direction {
        case .incoming: return l10n.incoming
        case .outgoing: return l10n.outgoing
        case .missed: return l10n.missed
        }
    }
}

/// Full-screen active call (simulated 1.8 s handshake, then a live timer).
struct InCallView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n
    @Environment(\.dismiss) private var dismiss

    let peerId: String
    let video: Bool

    @State private var connected = false
    @State private var elapsedSec = 0
    @State private var muted = false
    @State private var speaker = false
    @State private var timer: Timer?

    private var peer: FluxUser? {
        backend.userById(peerId)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)
            Text(peer?.name ?? "?")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.white)

            Text(connected ? String(format: "%02d:%02d", elapsedSec / 60, elapsedSec % 60) : l10n.calling)
                .font(.system(size: 16).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 8)

            Spacer()

            ZStack {
                if connected {
                    PulseRing()
                }
                FluxAvatarView(user: peer, size: 120)
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 3).padding(-4))
            }

            Spacer()

            HStack(spacing: 28) {
                controlButton(
                    active: muted,
                    systemImage: muted ? "mic.slash.fill" : "mic.fill",
                    activeIconColor: FluxColors.danger
                ) {
                    muted.toggle()
                }

                Button {
                    Haptics.medium()
                    stopTimer()
                    Task {
                        await backend.logCall(
                            peerId: peerId,
                            type: video ? .video : .audio,
                            direction: .outgoing,
                            durationSec: elapsedSec
                        )
                        dismiss()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(FluxColors.danger)
                            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 76, height: 76)
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.92))

                controlButton(
                    active: speaker,
                    systemImage: speaker ? "volume.3.fill" : "volume.1.fill",
                    activeIconColor: FluxColors.blue
                ) {
                    speaker.toggle()
                }
            }

            Text(l10n.endCall)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 10)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FluxColors.gradientCall.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                connected = true
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    Task { @MainActor in
                        elapsedSec += 1
                    }
                }
            }
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func controlButton(
        active: Bool,
        systemImage: String,
        activeIconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(active ? Color.white : Color.white.opacity(0.16))
                Image(systemName: systemImage)
                    .font(.system(size: 24))
                    .foregroundStyle(active ? activeIconColor : .white)
            }
            .frame(width: 62, height: 62)
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.92))
    }
}

/// Expanding pulse ring behind the avatar while connected.
private struct PulseRing: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .stroke(.white.opacity(0.45), lineWidth: 2)
            .frame(width: 132, height: 132)
            .scaleEffect(pulsing ? 1.28 : 1)
            .opacity(pulsing ? 0 : 0.9)
            .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulsing)
            .onAppear { pulsing = true }
    }
}
