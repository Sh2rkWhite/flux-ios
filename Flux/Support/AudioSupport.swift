import Foundation
import AVFoundation
import SwiftUI

// MARK: - Voice recorder

/// AAC voice recorder for chat voice messages (the counterpart of the
/// Android `record` plugin usage).
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var elapsedMs: Int = 0

    private var recorder: AVAudioRecorder?
    private var fileUrl: URL?
    private var timer: Timer?

    /// Requests mic permission and starts recording. Returns false when
    /// permission was denied.
    func start() async -> Bool {
        guard await withCheckedContinuation({ continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }) else { return false }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)

        let url = FluxMediaStore.directory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.record()
            fileUrl = url
            elapsedMs = 0
            recording = true
            Haptics.medium()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let recorder = self.recorder else { return }
                    self.elapsedMs = Int(recorder.currentTime * 1000)
                }
            }
            return true
        } catch {
            return false
        }
    }

    /// Stops recording. Returns (path, durationMs) when the recording is
    /// long enough to send, nil otherwise (or on cancel).
    func stop(send: Bool) -> (String, Int)? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard send, let fileUrl, elapsedMs > 300 else {
            if let fileUrl {
                try? FileManager.default.removeItem(at: fileUrl)
            }
            self.fileUrl = nil
            return nil
        }
        let result = (fileUrl.path, elapsedMs)
        self.fileUrl = nil
        return result
    }
}

// MARK: - Voice message playback

/// Shared single-voice-message player (one bubble plays at a time).
@MainActor
final class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()

    @Published private(set) var playingMessageId: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentDurationMs: Int = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(messageId: String, path: String?) {
        if playingMessageId == messageId {
            stopPlayback()
            return
        }
        if let path, FluxMedia.isStorageRef(path) {
            Task { await playRemote(messageId: messageId, ref: path) }
            return
        }
        guard let path, let url = URL(string: path), FileManager.default.fileExists(atPath: path) else {
            stopPlayback()
            return
        }
        startPlayback(messageId: messageId, url: url)
    }

    private func playRemote(messageId: String, ref: String) async {
        let objectPath = FluxMedia.objectPath(of: ref)
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FluxVoiceCache", isDirectory: true)
        let localUrl = cacheDir.appendingPathComponent(objectPath.replacingOccurrences(of: "/", with: "_"))
        if !FileManager.default.fileExists(atPath: localUrl.path) {
            guard let remoteUrl = await FluxMedia.downloadURL(for: ref) else { return }
            do {
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                let (tempUrl, _) = try await URLSession.shared.download(from: remoteUrl)
                try? FileManager.default.removeItem(at: localUrl)
                try FileManager.default.moveItem(at: tempUrl, to: localUrl)
            } catch {
                print("Flux: voice download failed (\(objectPath)): \(error.localizedDescription)")
                return
            }
        }
        guard playingMessageId != messageId else { return }
        startPlayback(messageId: messageId, url: localUrl)
    }

    private func startPlayback(messageId: String, url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            playingMessageId = messageId
            currentDurationMs = Int((player?.duration ?? 0) * 1000)
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let player = self.player else { return }
                    self.progress = player.duration > 0 ? player.currentTime / player.duration : 0
                    if !player.isPlaying {
                        self.stopPlayback()
                    }
                }
            }
        } catch {
            stopPlayback()
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        playingMessageId = nil
        progress = 0
        currentDurationMs = 0
    }
}
