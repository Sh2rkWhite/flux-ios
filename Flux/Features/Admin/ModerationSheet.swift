import SwiftUI

/// Admin moderation sheet (spec 0.7): Mute blocks starting NEW dialogs,
/// Freeze makes the account read-only. Mirrors the Android sheet.
struct ModerationSheet: View {
    @EnvironmentObject var backend: LocalBackend
    @Environment(\.dismiss) private var dismiss

    let user: FluxUser

    private struct Duration: Identifiable {
        let label: String
        let seconds: Int
        var id: Int { seconds }
    }

    private static let durations: [Duration] = [
        Duration(label: "1 час", seconds: 3_600),
        Duration(label: "24 часа", seconds: 86_400),
        Duration(label: "7 дней", seconds: 7 * 86_400),
        Duration(label: "30 дней", seconds: 30 * 86_400),
    ]

    @State private var muteSeconds = 86_400
    @State private var freezeSeconds = 86_400
    @State private var muteReason = ""
    @State private var freezeReason = ""
    @State private var busy = false

    private var title: String {
        "Модерация — " + (user.username.map { "@\($0)" } ?? user.fluxId)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(FluxColors.separator)
                .frame(width: 40, height: 4)
                .padding(.top, 10)

            Text(title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(FluxColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 16, leading: 20, bottom: 12, trailing: 20))

            ScrollView {
                VStack(spacing: 12) {
                    sectionCard(
                        emoji: "🔇",
                        title: "Mute",
                        subtitle: "Запрещает начинать новые диалоги. Текущие чаты работают.",
                        active: user.isMuted,
                        untilMs: user.mutedUntilMs,
                        reason: user.mutedReason,
                        seconds: muteSeconds,
                        onSeconds: { muteSeconds = $0 },
                        reasonText: $muteReason,
                        applyLabel: "Замьютить",
                        onApply: { apply(mute: true) },
                        onLift: { lift(mute: true) }
                    )
                    sectionCard(
                        emoji: "❄️",
                        title: "Freeze",
                        subtitle: "Аккаунт становится read-only: вход и чтение работают, любые изменения заблокированы.",
                        active: user.isFrozen,
                        untilMs: user.frozenUntilMs,
                        reason: user.frozenReason,
                        seconds: freezeSeconds,
                        onSeconds: { freezeSeconds = $0 },
                        reasonText: $freezeReason,
                        applyLabel: "Заморозить",
                        onApply: { apply(mute: false) },
                        onLift: { lift(mute: false) }
                    )
                }
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 24, trailing: 16))
            }
        }
        .background(Material.ultraThinMaterial)
    }

    // MARK: Sections

    private func sectionCard(
        emoji: String,
        title: String,
        subtitle: String,
        active: Bool,
        untilMs: Int,
        reason: String?,
        seconds: Int,
        onSeconds: @escaping (Int) -> Void,
        reasonText: Binding<String>,
        applyLabel: String,
        onApply: @escaping () -> Void,
        onLift: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(emoji) \(title)")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(FluxColors.textPrimary)
                Spacer()
                if active {
                    Text("до \(formatCallTime(untilMs))")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(FluxColors.warning)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(FluxColors.warning.opacity(0.15))
                        )
                }
            }

            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(FluxColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if active, let reason, !reason.isEmpty {
                Text("Причина: \(reason)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(FluxColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowLayout(spacing: 8) {
                ForEach(Self.durations) { duration in
                    chip(label: duration.label, selected: seconds == duration.seconds) {
                        onSeconds(duration.seconds)
                    }
                }
            }
            .padding(.top, 2)

            FluxTextField(text: reasonText, hint: "Причина (видна пользователю)")

            if active {
                HStack(spacing: 10) {
                    applyButton(label: applyLabel, emoji: emoji, action: onApply)
                    Button {
                        Haptics.light()
                        onLift()
                    } label: {
                        Text("Снять")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(FluxColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(FluxColors.separator, lineWidth: 1)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(busy)
                }
            } else {
                applyButton(label: applyLabel, emoji: emoji, action: onApply)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FluxColors.surface)
        )
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? Color.white : FluxColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(selected ? AnyShapeStyle(FluxColors.gradient) : AnyShapeStyle(FluxColors.surfaceGray))
                )
        }
        .buttonStyle(.plain)
    }

    private func applyButton(label: String, emoji: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 15))
                Text(label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FluxColors.gradient)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(busy)
    }

    // MARK: Actions

    private func apply(mute: Bool) {
        guard !busy, backend.me?.isAdmin == true else { return }
        busy = true
        let seconds = mute ? muteSeconds : freezeSeconds
        let reason = (mute ? muteReason : freezeReason).trimmingCharacters(in: .whitespacesAndNewlines)
        let untilMs = Int(Date().timeIntervalSince1970 * 1000) + seconds * 1000
        backend.setModeration(user, mute: mute, untilMs: untilMs, reason: reason.isEmpty ? nil : reason)
        dismiss()
    }

    private func lift(mute: Bool) {
        guard !busy, backend.me?.isAdmin == true else { return }
        busy = true
        backend.setModeration(user, mute: mute, untilMs: 0, reason: nil)
        dismiss()
    }
}
