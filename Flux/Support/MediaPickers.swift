import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Media storage

enum FluxMediaStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluxMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Copies the picked image data into the media store and returns the
    /// absolute file path (messages reference local paths).
    static func saveImage(_ data: Data, prefix: String) -> String? {
        let url = directory.appendingPathComponent("\(prefix)-\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    static func saveFile(at sourceUrl: URL, preferredName: String?) -> (path: String, name: String, size: Int)? {
        let name = preferredName ?? sourceUrl.lastPathComponent
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        do {
            // Access security-scoped bookmarks if needed.
            let accessed = sourceUrl.startAccessingSecurityScopedResource()
            defer { if accessed { sourceUrl.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: sourceUrl, to: url)
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            return (url.path, name, size)
        } catch {
            return nil
        }
    }
}

// MARK: - Photo library picker

/// PHPicker wrapper returning image data (gallery selection).
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onPicked: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker
        init(_ parent: PhotoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let provider = results.first?.itemProvider else { return }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                DispatchQueue.main.async {
                    self.parent.onPicked(data)
                }
            }
        }
    }
}

// MARK: - Camera picker

/// UIImagePickerController wrapper for capturing a photo.
struct CameraPicker: UIViewControllerRepresentable {
    let onPicked: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.dismiss()
            let data = (info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage)?
                .jpegData(compressionQuality: 0.85)
            if let data {
                DispatchQueue.main.async {
                    self.parent.onPicked(data)
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Document picker

/// UIDocumentPicker wrapper for arbitrary file attachments.
struct DocumentPicker: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.dismiss()
            if let url = urls.first {
                DispatchQueue.main.async {
                    self.parent.onPicked(url)
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - Attachment picker enum

enum AttachmentKind: String, CaseIterable, Identifiable {
    case gallery, camera, file

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .gallery: return "photo.on.rectangle"
        case .camera: return "camera"
        case .file: return "paperclip"
        }
    }

    var title: String {
        switch self {
        case .gallery: return "Галерея"
        case .camera: return "Камера"
        case .file: return "Файл"
        }
    }
}
