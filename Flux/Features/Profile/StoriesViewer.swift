import SwiftUI

/// Fullscreen story viewer with auto-advance and tap navigation.
struct StoriesViewer: View {
    @Environment(\.dismiss) private var dismiss

    let stories: [FluxStory]
    let startIndex: Int

    @State private var index = 0
    @State private var progress: Double = 0

    var body: some View {
        let safeIndex = min(index, max(0, stories.count - 1))
        let story = stories.isEmpty ? nil : stories[safeIndex]

        ZStack {
            Color.black.ignoresSafeArea()

            if let story {
                RemoteMediaImage(path: story.mediaPath) {
                    Rectangle().fill(FluxColors.gradient)
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress bars
                    HStack(spacing: 4) {
                        ForEach(0..<stories.count, id: \.self) { i in
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.3))
                                    Capsule().fill(.white)
                                        .frame(width: i < safeIndex ? geometry.size.width : (i == safeIndex ? geometry.size.width * progress : 0))
                                }
                            }
                            .frame(height: 3)
                        }
                    }
                    .padding(.horizontal, 12)

                    HStack {
                        Spacer()
                        Button {
                            Haptics.light()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(.white.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)

                    Spacer()

                    if let caption = story.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(
                                Rectangle()
                                    .fill(Color.black.opacity(0.35))
                            )
                    }
                }

                // Tap zones: left = previous, right = next.
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { advance(-1) }
                    Color.clear
                        .frame(width: 80)
                        .contentShape(Rectangle())
                        .onTapGesture { dismiss() }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { advance(1) }
                }
            } else {
                Text("Нет историй")
                    .foregroundStyle(.white)
            }
        }
        .task(id: safeIndex) {
            progress = 0
            guard !stories.isEmpty else { return }
            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if Task.isCancelled { return }
                progress += 0.05
                if progress >= 1 {
                    advance(1)
                    return
                }
            }
        }
    }

    private func advance(_ direction: Int) {
        Haptics.selection()
        let next = index + direction
        if next < 0 {
            index = 0
        } else if next >= stories.count {
            dismiss()
        } else {
            index = next
        }
        progress = 0
    }
}
