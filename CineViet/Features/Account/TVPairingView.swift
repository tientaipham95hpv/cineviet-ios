import SwiftUI
import AVFoundation

struct TVPairingView: View {
    let service: AuthenticationServicing
    @State private var code = ""
    @State private var message: String?
    @State private var isSubmitting = false
    @State private var showScanner = false

    var body: some View {
        Form {
            Section {
                Text("Mở CineViet trên TV, chọn Đăng nhập bằng mã rồi nhập mã hiển thị trên TV tại đây.")
                    .foregroundStyle(.secondary)
                TextField("Mã 6 số", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(6)) }
                Button { showScanner = true } label: { Label("Quét mã QR", systemImage: "qrcode.viewfinder") }
            }
            Section {
                Button { Task { await confirm() } } label: {
                    HStack { Spacer(); if isSubmitting { ProgressView() } else { Text("Xác nhận đăng nhập TV").bold() }; Spacer() }
                }
                .disabled(code.count < 6 || isSubmitting)
            }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
        }
        .navigationTitle("Đăng nhập TV")
        .sheet(isPresented: $showScanner) { QRScannerView { value in code = String(value.filter(\.isNumber).prefix(6)); showScanner = false } }
    }

    private func confirm() async {
        isSubmitting = true; defer { isSubmitting = false }
        do { try await service.confirmTV(code: code); message = "Đã xác nhận. TV sẽ tự động đăng nhập." }
        catch { message = error.localizedDescription }
    }
}

private struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController { ScannerController(onCode: onCode) }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

private final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let onCode: (String) -> Void
    private let session = AVCaptureSession()
    init(onCode: @escaping (String) -> Void) { self.onCode = onCode; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input); let output = AVCaptureMetadataOutput(); guard session.canAddOutput(output) else { return }
        session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session); layer.videoGravity = .resizeAspectFill; layer.frame = view.bounds; view.layer.addSublayer(layer)
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        let digits = value.filter(\.isNumber); guard digits.count >= 6 else { return }; session.stopRunning(); onCode(String(digits.prefix(6)))
    }
}
