//
//  FriendQR.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//
//  QR code generation + scanning for the low-friction "add a friend" flow.
//  Scanning a friend's QR sends them a request; they accept on their device and
//  the two-way safety link is formed. No accounts, no typing codes.
//

import SwiftUI
import AVFoundation
import AudioToolbox
import CoreImage.CIFilterBuiltins

/// Encodes/decodes the tiny payload a Checkpoint QR carries: a userId + name,
/// wrapped in a custom scheme so we can ignore unrelated QR codes.
enum FriendQR {
    private static let scheme = "checkpoint"

    static func payload(id: String, name: String) -> String {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = "add"
        comps.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "name", value: name),
        ]
        return comps.url?.absoluteString ?? id
    }

    static func parse(_ string: String) -> (id: String, name: String)? {
        guard let comps = URLComponents(string: string),
              comps.scheme == scheme,
              let id = comps.queryItems?.first(where: { $0.name == "id" })?.value,
              !id.isEmpty else { return nil }
        let name = comps.queryItems?.first(where: { $0.name == "name" })?.value ?? "Friend"
        return (id, name)
    }

    /// Renders a crisp QR image for the given string, or nil if generation fails.
    static func image(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Scale up so the small native output isn't blurry when displayed large.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Scanner

/// A live camera QR scanner. Calls `onFound` exactly once with the decoded string.
struct QRScannerView: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onFound = { context.coordinator.deliver($0) }
        return controller
    }

    func updateUIViewController(_ controller: QRScannerController, context: Context) {}

    final class Coordinator {
        private let onFound: (String) -> Void
        private var delivered = false

        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        /// Guards against the metadata callback firing repeatedly for one code.
        func deliver(_ code: String) {
            guard !delivered else { return }
            delivered = true
            onFound(code)
        }
    }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "qr.scanner.session")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        sessionQueue.async { [session] in session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let string = object.stringValue else { return }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        onFound?(string)
    }
}

// MARK: - Views

/// Big, scannable QR of the current user, plus their code as a fallback.
struct MyQRView: View {
    @ObservedObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss

    private var qrImage: UIImage? {
        FriendQR.image(from: FriendQR.payload(id: userManager.userId, name: DeviceIdentity.currentName))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Have a friend scan this to add you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 260)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                }

                VStack(spacing: 4) {
                    Text("Or share your code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(userManager.myCode)
                        .font(.system(.title2, design: .monospaced).bold())
                        .textSelection(.enabled)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("My QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Full-screen scanner sheet. On a valid Checkpoint QR it sends a request and
/// reports the outcome, then dismisses.
struct ScanFriendView: View {
    @ObservedObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss

    @State private var resultMessage: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView { code in handleScan(code) }
                    .ignoresSafeArea()

                VStack {
                    Spacer()
                    Text("Point at a friend's Checkpoint QR code")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 40)
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(isError ? "Couldn't add" : "Request sent",
                   isPresented: Binding(get: { resultMessage != nil },
                                        set: { if !$0 { resultMessage = nil } })) {
                Button("OK") { dismiss() }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    private func handleScan(_ code: String) {
        guard let parsed = FriendQR.parse(code) else {
            isError = true
            resultMessage = "That doesn't look like a Checkpoint code."
            return
        }
        userManager.sendFriendRequest(toUserId: parsed.id, name: parsed.name) { error in
            isError = error != nil
            resultMessage = error ?? "\(parsed.name) will get your request to connect."
        }
    }
}
