import SwiftUI

/// Message composer: attachment button, morphing text/voice button, and
/// the reply/edit context banner (mirrors the Android ChatInputBar).
struct ChatInputBar: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n

    let onSend: (String) -> Void
    let onAttach: () -> Void
    let onMicTap: () -> Void
    @Binding var replyTarget: FluxMessage?
    @Binding var editTarget: FluxMessage?

    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            if replyTarget != nil || editTarget != nil {
                contextBanner
            }
            HStack(spacing: 6) {
                Button {
                    Haptics.light()
                    onAttach()
                } label: {
                    ZStack {
                        Circle().fill(FluxColors.surfaceGray)
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(FluxColors.textSecondary)
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.9))

                TextField(l10n.message, text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 15.5))
                    .foregroundStyle(FluxColors.textPrimary)
                    .focused($focused)
                    .submitLabel(.send)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(FluxColors.surfaceGray)
                    )

                if trimmedText.isEmpty {
                    Button {
                        Haptics.light()
                        onMicTap()
                    } label: {
                        ZStack {
                            Circle().fill(FluxColors.surfaceGray)
                            Image(systemName: "mic.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(FluxColors.blue)
                        }
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(ScaleButtonStyle(scale: 0.9))
                } else {
                    Button {
                        let value = trimmedText
                        text = ""
                        Haptics.light()
                        onSend(value)
                    } label: {
                        ZStack {
                            Circle().fill(FluxColors.gradient)
                                .shadow(color: FluxColors.blue.opacity(0.32), radius: 10, y: 3)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(ScaleButtonStyle(scale: 0.9))
                }
            }
            .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        }
        .background(
            VStack(spacing: 0) {
                Divider().overlay(FluxColors.separator.opacity(0.5))
                FluxColors.surface
            }
            .ignoresSafeArea(edges: .bottom)
        )
        .onChange(of: replyTarget) { newValue in
            if newValue != nil { focused = true }
        }
        .onChange(of: editTarget) { newValue in
            if let newValue {
                text = newValue.text
                focused = true
            }
        }
    }

    @ViewBuilder
    private var contextBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: editTarget != nil ? "pencil" : "arrowshape.turn.up.left")
                .font(.system(size: 15))
                .foregroundStyle(FluxColors.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(editTarget != nil ? l10n.edit : l10n.reply)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FluxColors.blue)
                Text(contextPreviewText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(FluxColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                replyTarget = nil
                editTarget = nil
                if editTarget != nil { text = "" }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15))
                    .foregroundStyle(FluxColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 8, leading: 14, bottom: 0, trailing: 10))
    }

    private var contextPreviewText: String {
        let target = editTarget ?? replyTarget
        guard let target else { return "" }
        switch target.kind {
        case .text: return target.text
        case .image: return "📷 Медиа"
        case .voice: return "🎤 \(l10n.voiceMessage)"
        case .file: return "📎 \(l10n.file)"
        }
    }
}

/// The voice-recording bar replacing the input row while recording.
struct RecordingBar: View {
    @ObservedObject var recorder: VoiceRecorder
    let onDone: (Bool) -> Void

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(FluxColors.danger)
                .frame(width: 10, height: 10)
                .scaleEffect(pulse ? 1.25 : 1)
                .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: pulse)

            Text(formatDurationMs(recorder.elapsedMs))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(FluxColors.danger)

            Text("Голосовое сообщение")
                .font(.system(size: 12))
                .foregroundStyle(FluxColors.textSecondary)

            Spacer()

            Button {
                Haptics.medium()
                onDone(false)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18))
                    .foregroundStyle(FluxColors.danger)
            }
            .buttonStyle(ScaleButtonStyle())

            Button {
                Haptics.light()
                onDone(true)
            } label: {
                ZStack {
                    Circle().fill(FluxColors.gradient)
                        .frame(width: 38, height: 38)
                        .shadow(color: FluxColors.blue.opacity(0.32), radius: 8, y: 2)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.9))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(FluxColors.danger.opacity(0.07))
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(FluxColors.surface)
        .onAppear { pulse = true }
    }
}
