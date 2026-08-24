import SwiftUI
import UIKit
import AVFoundation
import CoreImage.CIFilterBuiltins

// MARK: - QR generation

/// Generates a QR image for the Flux deep link `flux://u/<fluxId>` using
/// CoreImage — no third-party dependency needed.
enum QRCodeGenerator {
    static func qrImage(for string: String, scale: CGFloat = 10) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// The safe public deep link encoded by every Flux QR code.
    static func deepLink(fluxId: String) -> String {
        "flux://u/\(fluxId)"
    }

    /// FluxCoinsBot quick-transfer payload: `flux://pay/<FLUXID>` or
    /// `flux://pay/<FLUXID>?amount=<N>` (mirrors the Dart
    /// `fluxPayQrPayload` — both platforms scan and generate the same codes).
    static func payPayload(fluxId: String, amount: Int? = nil) -> String {
        if let amount, amount > 0 {
            return "flux://pay/\(fluxId)?amount=\(amount)"
        }
        return "flux://pay/\(fluxId)"
    }
}

/// QR view with a white inset card and the FluxID caption.
struct QRCodeView: View {
    let fluxId: String
    var size: CGFloat = 220

    var body: some View {
        VStack(spacing: 14) {
            if let image = QRCodeGenerator.qrImage(for: QRCodeGenerator.deepLink(fluxId: fluxId)) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.white)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            }
            Text(fluxId)
                .font(.system(size: 15, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(FluxColors.textPrimary)
        }
    }
}

// MARK: - QR scanning

/// AVCaptureMetadataOutput scanner wrapped for SwiftUI. Requests camera
/// permission on appear and reports scanned payload strings on the main
/// actor. `scanningEnabled` pauses/resumes delivery.
struct QRScannerController: UIViewControllerRepresentable {
    var onScanned: (String) -> Void
    @Binding var isScanningEnabled: Bool

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onScanned = onScanned
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        uiViewController.scanningEnabled = isScanningEnabled
    }

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScanned: ((String) -> Void)?
        var scanningEnabled = true {
            didSet { scanDelegate?.scanningEnabled = scanningEnabled }
        }

        private var captureSession: AVCaptureSession?
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var scanDelegate: ScanDelegate?

        final class ScanDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
            var scanningEnabled = true
            var handler: ((String) -> Void)?
            private var lastScanAt = Date.distantPast

            func metadataOutput(
                _ output: AVCaptureMetadataOutput,
                didOutput metadataObjects: [AVMetadataObject],
                from connection: AVCaptureConnection
            ) {
                guard scanningEnabled else { return }
                guard Date().timeIntervalSince(lastScanAt) > 1.2 else { return }
                guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                      object.type == .qr,
                      let value = object.stringValue else { return }
                lastScanAt = Date()
                DispatchQueue.main.async {
                    self.handler?(value)
                }
            }
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                setupSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        if granted { self?.setupSession() }
                    }
                }
            default:
                showPermissionDenied()
            }
        }

        private func showPermissionDenied() {
            let label = UILabel()
            label.text = "Нужен доступ к камере для сканирования QR-кода"
            label.textColor = .white
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            ])
        }

        private func setupSession() {
            let session = AVCaptureSession()
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                showPermissionDenied()
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            let delegate = ScanDelegate()
            delegate.scanningEnabled = scanningEnabled
            delegate.handler = { [weak self] value in
                self?.onScanned?(value)
            }
            output.setMetadataObjectsDelegate(delegate, queue: .main)
            output.metadataObjectTypes = [.qr]

            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            self.previewLayer = previewLayer
            scanDelegate = delegate

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                session.startRunning()
                DispatchQueue.main.async {
                    guard let self else { return }
                    previewLayer.frame = self.view.bounds
                    self.view.layer.insertSublayer(previewLayer, at: 0)
                }
            }
            captureSession = session
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            captureSession?.stopRunning()
        }
    }
}

/// Parses a scanned payload: returns the FluxID from a Flux deep link or a
/// bare `FLX-…` string, nil otherwise.
enum QRCodeParser {
    static func fluxId(from payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("flux://u/") {
            let id = String(trimmed.dropFirst("flux://u/".count)).uppercased()
            return id.matchesFluxIdPattern ? id : nil
        }
        let upper = trimmed.uppercased()
        return upper.matchesFluxIdPattern ? upper : nil
    }

    /// Parses a FluxCoinsBot payment QR payload (`flux://pay/…`); returns
    /// nil for anything else (mirrors the Dart `parsePayQrPayload`).
    static func payQr(from payload: String) -> FluxPayQr? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("flux://pay/") else { return nil }
        let rest = String(trimmed.dropFirst("flux://pay/".count))
        let parts = rest.components(separatedBy: "?")
        let fluxId = (parts.first ?? "").uppercased()
        guard fluxId.matchesFluxIdPattern else { return nil }
        var amount: Int?
        if parts.count > 1 {
            for param in parts.dropFirst().joined(separator: "?").components(separatedBy: "&") {
                let kv = param.components(separatedBy: "=")
                if kv.count == 2, kv[0] == "amount" {
                    amount = Int(kv[1])
                }
            }
        }
        return FluxPayQr(fluxId: fluxId, amount: amount)
    }
}

/// The parsed result of a FluxCoinsBot payment QR payload.
struct FluxPayQr {
    let fluxId: String
    let amount: Int?
}

extension String {
    /// `FLX-` followed by 8 identifier characters (the FluxID alphabet).
    var matchesFluxIdPattern: Bool {
        guard count == 12, hasPrefix("FLX-") else { return false }
        let alphabet = Set("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return dropFirst(4).allSatisfy { alphabet.contains($0) }
    }
}
