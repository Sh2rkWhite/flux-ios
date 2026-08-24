import SwiftUI
import FirebaseCore
import FirebaseStorage

/// Remote media references shared with the Android client.
///
/// A reference is the `flux-storage:` prefix + a Storage object path, e.g.
/// `flux-storage:avatars/flx-abc123`. Object paths:
/// avatars → `avatars/{fluxId.lowercased()}`, banners → `banners/{fluxId}`,
/// chat media → `chat_media/{senderFluxId}/{messageId}.{ext}`.
enum FluxMedia {
    static let prefix = "flux-storage:"

    static func isStorageRef(_ path: String?) -> Bool {
        path?.hasPrefix(prefix) ?? false
    }

    static func objectPath(of ref: String) -> String {
        String(ref.dropFirst(prefix.count))
    }

    static func ext(of path: String, fallback: String = "bin") -> String {
        let value = (path as NSString).pathExtension.lowercased()
        return value.isEmpty ? fallback : value
    }

    private actor UrlCache {
        static let shared = UrlCache()
        private var urlCache: [String: URL] = [:]

        func get(_ key: String) -> URL? { urlCache[key] }
        func set(_ key: String, _ url: URL) { urlCache[key] = url }
    }

    /// Uploads a local file to the Storage object path and returns the
    /// `flux-storage:` reference, or nil on failure (the caller keeps the
    /// local path). Never throws — the default bucket may not exist yet.
    static func uploadFile(localPath: String, objectPath: String) async -> String? {
        guard FirebaseApp.app() != nil, !objectPath.isEmpty,
              FileManager.default.fileExists(atPath: localPath) else { return nil }
        do {
            let ref = Storage.storage().reference(withPath: objectPath)
            _ = try await ref.putFileAsync(from: URL(fileURLWithPath: localPath))
            return prefix + objectPath
        } catch {
            print("Flux: storage upload failed (\(objectPath)): \(error.localizedDescription)")
            return nil
        }
    }

    /// Resolves a `flux-storage:` reference to a download URL (cached).
    /// Returns nil for non-references and on failure.
    static func downloadURL(for ref: String?) async -> URL? {
        guard let ref, isStorageRef(ref), FirebaseApp.app() != nil else { return nil }
        let path = objectPath(of: ref)
        guard !path.isEmpty else { return nil }
        if let cached = await UrlCache.shared.get(path) { return cached }
        do {
            let url = try await Storage.storage().reference(withPath: path).downloadURL()
            await UrlCache.shared.set(path, url)
            return url
        } catch {
            print("Flux: storage download URL failed (\(path)): \(error.localizedDescription)")
            return nil
        }
    }
}

/// Renders a media path that is either a local file or a `flux-storage:`
/// reference. Remote refs load via AsyncImage once their download URL
/// resolves; local files load synchronously; anything unresolvable shows
/// the fallback.
struct RemoteMediaImage<Fallback: View>: View {
    let path: String?
    @ViewBuilder var fallback: () -> Fallback

    @State private var remoteUrl: URL?

    private var localImage: UIImage? {
        guard let path, !FluxMedia.isStorageRef(path) else { return nil }
        return UIImage(contentsOfFile: path)
    }

    var body: some View {
        Group {
            if let path, FluxMedia.isStorageRef(path) {
                if let remoteUrl {
                    AsyncImage(url: remoteUrl) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            fallback()
                        }
                    }
                } else {
                    fallback()
                }
            } else if let localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback()
            }
        }
        .task(id: path) {
            remoteUrl = await FluxMedia.downloadURL(for: path)
        }
    }
}
