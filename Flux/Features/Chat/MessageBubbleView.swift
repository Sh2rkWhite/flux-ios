import SwiftUI

/// A single chat message bubble with all payload kinds, receipts,
/// reactions and the system-message variant (mirrors the Android
/// MessageBubble).
struct MessageBubbleView: View {
    @EnvironmentObject var backend: LocalBackend
    @EnvironmentObject var l10n: FluxL10n
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared

    let message: FluxMessage
    let isMine: Bool
    let showTail: Bool
    let showTopGap: Bool
    let onLongPress: () -> Void
    let replyMessage: FluxMessage?

    private var bubbleColor: AnyShapeStyle {
        isMine ? AnyShapeStyle(FluxColors.gradient) : AnyShapeStyle(FluxColors.surface)
    }

    var body: some View {
        Group {
            if message.isSystemMessage {
                systemCard
            } else {
                regularBubble
            }
        }
        .padding(.top, showTopGap ? 10 : 2)
    }

    // MARK: Regular bubble

    private var regularBubble: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isMine { Spacer(minLength: 0) }
            VStack(alignment: .trailing, spacing: 3) {
                bubbleContent
                    .background(bubbleShape)
                if !message.reactions.isEmpty {
                    reactionsRow
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: isMine ? .trailing : .leading)
            if !isMine { Spacer(minLength: 0) }
        }
        .padding(.leading, isMine ? 56 : 0)
        .padding(.trailing, isMine ? 0 : 56)
        .contentShape(Rectangle())
        .onLongPressGesture(perform: onLongPress)
    }

    private var bubbleShape: some View {
        RoundedCorners(
            radius: 20,
            tailCorner: isMine ? .br : .bl,
            showTail: showTail
        )
        .fill(bubbleColor)
        .shadow(color: Color(hex: 0x1A2340).opacity(isMine ? 0 : 0.05), radius: 10, y: 3)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let replyMessage {
                replyPreview(replyMessage)
            }
            payload
            metaRow
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(EdgeInsets(top: message.kind == .image ? 5 : 9, leading: 14, bottom: message.kind == .image ? 8 : 9, trailing: 14))
    }

    @ViewBuilder
    private func replyPreview(_ original: FluxMessage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(replyPreviewText(original))
                .font(.system(size: 13))
                .foregroundStyle(isMine ? .white.opacity(0.85) : FluxColors.textPrimary)
                .lineLimit(2)
        }
        .padding(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isMine ? Color.white.opacity(0.14) : FluxColors.blue.opacity(0.14))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isMine ? Color.white.opacity(0.7) : FluxColors.blue)
                .frame(width: 3)
                .padding(.vertical, 4)
        }
        .padding(.bottom, 7)
    }

    private func replyPreviewText(_ original: FluxMessage) -> String {
        switch original.kind {
        case .text: return original.text
        case .image: return "📷 Фото"
        case .voice: return "🎤 Голосовое сообщение"
        case .file: return "📎 Файл"
        }
    }

    // MARK: Payload

    @ViewBuilder
    private var payload: some View {
        switch message.kind {
        case .text:
            Text(message.text)
                .font(.system(size: 16))
                .foregroundStyle(isMine ? Color.white : FluxColors.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .image:
            imagePayload
        case .voice:
            voicePayload
        case .file:
            filePayload
        }
    }

    @ViewBuilder
    private var imagePayload: some View {
        if let path = message.mediaPath, let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipped()
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FluxColors.surfaceGray)
                .frame(width: 220, height: 160)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 26))
                            .foregroundStyle(FluxColors.textTertiary)
                        Text("Фото недоступно")
                            .font(.system(size: 12))
                            .foregroundStyle(FluxColors.textTertiary)
                    }
                )
        }
    }

    private var voicePayload: some View {
        let isPlaying = audioPlayer.playingMessageId == message.id
        return HStack(spacing: 10) {
            Button {
                Haptics.light()
                audioPlayer.toggle(messageId: message.id, path: message.mediaPath)
            } label: {
                ZStack {
                    Circle()
                        .fill(isMine ? Color.white.opacity(0.22) : FluxColors.blueSoft)
                        .frame(width: 38, height: 38)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(isMine ? .white : FluxColors.blue)
                }
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.9))

            VStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill((isMine ? Color.white : FluxColors.textPrimary).opacity(0.18))
                        Capsule()
                            .fill(isMine ? Color.white : FluxColors.blue)
                            .frame(width: max(6, geometry.size.width * (isPlaying ? audioPlayer.progress : 0.02)))
                    }
                }
                .frame(width: 110, height: 4)
                Text(formatDurationMs(isPlaying && audioPlayer.currentDurationMs > 0 ? Int(Double(audioPlayer.currentDurationMs) * audioPlayer.progress) : message.voiceDurationMs))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(isMine ? Color.white.opacity(0.8) : FluxColors.textSecondary)
            }
        }
    }

    private var filePayload: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isMine ? Color.white.opacity(0.22) : FluxColors.blueSoft)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "doc.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(isMine ? .white : FluxColors.blue)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(message.fileName ?? l10n.file)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(isMine ? .white : FluxColors.textPrimary)
                    .lineLimit(1)
                if let size = message.fileSize {
                    Text(formatFileSize(size))
                        .font(.system(size: 12))
                        .foregroundStyle(isMine ? Color.white.opacity(0.75) : FluxColors.textSecondary)
                }
            }
        }
    }

    // MARK: Meta

    private var metaRow: some View {
        HStack(spacing: 4) {
            if message.expiresAtMs != nil {
                Image(systemName: "timer")
                    .font(.system(size: 10))
                    .foregroundStyle(isMine ? Color.white.opacity(0.7) : FluxColors.textTertiary)
            }
            if message.isEdited {
                Text("изм.")
                    .font(.system(size: 11))
                    .foregroundStyle(isMine ? Color.white.opacity(0.7) : FluxColors.textTertiary)
            }
            Text(formatTime(message.sentAtMs))
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(isMine ? Color.white.opacity(0.75) : FluxColors.textSecondary)
            if isMine {
                Image(systemName: message.isRead ? "checkmark" : "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(message.isRead ? Color(hex: 0xB7FFD9) : Color.white.opacity(0.65))
                if message.isRead {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xB7FFD9))
                        .offset(x: -7)
                }
            }
        }
        .padding(.top, 3)
    }

    // MARK: Reactions

    private var reactionsRow: some View {
        HStack(spacing: 5) {
            ForEach(Array(message.reactions.keys.sorted()), id: \.self) { emoji in
                HStack(spacing: 4) {
                    Text(emoji)
                        .font(.system(size: 13))
                    if let count = message.reactions[emoji]?.count, count > 0 {
                        Text("\(count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FluxColors.textSecondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(FluxColors.surface)
                        .overlay(Capsule().strokeBorder(FluxColors.separator, lineWidth: 1))
                        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                )
            }
        }
        .padding(.top, 2)
    }

    // MARK: System message

    private var systemCard: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(FluxColors.blueSoft)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 15))
                        .foregroundStyle(FluxColors.blue)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 13.5, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(Color(light: 0x4A5068, dark: 0xB0B8CC))
                Text(formatTime(message.sentAtMs))
                    .font(.system(size: 11))
                    .foregroundStyle(FluxColors.textTertiary)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: UIScreen.main.bounds.width * 0.82, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FluxColors.surface.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(FluxColors.blue.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }
}

// MARK: - Bubble shapes

/// Rounded rectangle with a small tail corner (6 pt) on the last message
/// of a group.
struct RoundedCorners: Shape {
    var radius: CGFloat
    var tailCorner: Corner
    var showTail: Bool

    enum Corner {
        case tl, tr, bl, br
    }

    func path(in rect: CGRect) -> Path {
        let tailRadius: CGFloat = showTail ? 6 : radius
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - (tailCorner == .br ? tailRadius : radius)))
        path.addArc(
            center: CGPoint(x: rect.maxX - (tailCorner == .br ? tailRadius : radius), y: rect.maxY - (tailCorner == .br ? tailRadius : radius)),
            radius: tailCorner == .br ? tailRadius : radius,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + (tailCorner == .bl ? tailRadius : radius), y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + (tailCorner == .bl ? tailRadius : radius), y: rect.maxY - (tailCorner == .bl ? tailRadius : radius)),
            radius: tailCorner == .bl ? tailRadius : radius,
            startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
