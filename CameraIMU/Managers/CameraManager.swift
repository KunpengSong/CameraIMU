import AVFoundation
import Foundation

class CameraManager: NSObject, ObservableObject {
    let captureSession = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let sessionQueue = DispatchQueue(label: "camera-session")

    @Published var isSessionRunning = false
    @Published var recordingFinished = false
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var currentCameraIndex: Int = 0

    private var currentVideoInput: AVCaptureDeviceInput?
    // Local copies used on sessionQueue (not @Published, no main-thread dependency)
    private var discoveredCameras: [AVCaptureDevice] = []
    private var selectedCameraIndex: Int = 0
    var onRecordingFinished: ((URL?, Error?) -> Void)?

    // QR code detection
    var onQRCodeDetected: ((String) -> Void)?
    private var lastQRScanTime: TimeInterval = 0
    private let qrScanInterval: TimeInterval = 0.5  // ~2fps

    var currentCameraName: String {
        guard !availableCameras.isEmpty else { return "No Camera" }
        return availableCameras[currentCameraIndex].localizedName
    }

    func configure() {
        sessionQueue.async { [weak self] in
            self?.discoverCameras()
            self?.setupSession()
        }
    }

    private func discoverCameras() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: .back
        )

        let cameras = discoverySession.devices

        // Default to ultra-wide (0.5x) if available, otherwise wide-angle
        let preferredIndex = cameras.firstIndex {
            $0.deviceType == .builtInUltraWideCamera
        } ?? cameras.firstIndex {
            $0.deviceType == .builtInWideAngleCamera && $0.position == .back
        } ?? 0

        // Store locally for immediate use on sessionQueue
        discoveredCameras = cameras
        selectedCameraIndex = preferredIndex

        // Also publish to main thread for UI
        DispatchQueue.main.async {
            self.availableCameras = cameras
            self.currentCameraIndex = preferredIndex
        }
    }

    private func setupSession() {
        guard !discoveredCameras.isEmpty else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        // Video input
        let device = discoveredCameras[selectedCameraIndex]
        guard let videoInput = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(videoInput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(videoInput)
        currentVideoInput = videoInput

        // Audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }

        // Movie output
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
        }

        // QR code metadata output
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            if metadataOutput.availableMetadataObjectTypes.contains(.qr) {
                metadataOutput.metadataObjectTypes = [.qr]
            }
        }

        captureSession.commitConfiguration()
        captureSession.startRunning()

        DispatchQueue.main.async {
            self.isSessionRunning = self.captureSession.isRunning
        }
    }

    func switchCamera(to index: Int) {
        guard index >= 0, index < availableCameras.count, index != currentCameraIndex else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.captureSession.beginConfiguration()

            // Remove current video input
            if let currentInput = self.currentVideoInput {
                self.captureSession.removeInput(currentInput)
            }

            // Add new video input
            let newDevice = self.availableCameras[index]
            guard let newInput = try? AVCaptureDeviceInput(device: newDevice),
                  self.captureSession.canAddInput(newInput) else {
                // Rollback: re-add old input
                if let oldInput = self.currentVideoInput,
                   self.captureSession.canAddInput(oldInput) {
                    self.captureSession.addInput(oldInput)
                }
                self.captureSession.commitConfiguration()
                return
            }

            self.captureSession.addInput(newInput)
            self.currentVideoInput = newInput

            self.captureSession.commitConfiguration()

            DispatchQueue.main.async {
                self.currentCameraIndex = index
            }
        }
    }

    func startRecording(to url: URL) {
        guard captureSession.isRunning else { return }
        recordingFinished = false
        movieOutput.startRecording(to: url, recordingDelegate: self)
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }
}

extension CameraManager: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        // Throttle to ~2fps
        let now = CACurrentMediaTime()
        guard now - lastQRScanTime >= qrScanInterval else { return }
        lastQRScanTime = now

        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject,
                  readable.type == .qr,
                  let value = readable.stringValue else { continue }
            onQRCodeDetected?(value)
        }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.recordingFinished = true
            self.onRecordingFinished?(outputFileURL, error)
        }
    }
}
