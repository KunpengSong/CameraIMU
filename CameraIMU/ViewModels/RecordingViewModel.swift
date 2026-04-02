import AVFoundation
import Combine
import SwiftUI

@MainActor
class RecordingViewModel: ObservableObject {
    let cameraManager = CameraManager()
    let motionManager = MotionManager()

    @Published var isRecording = false
    @Published var recordings: [Recording] = []
    @Published var recordingDuration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var imuSampleCount: Int = 0
    @Published var lastQREvent: String?

    private static let qrPrefix = "CAMERAIMU:"
    private var lastQRCommandTime: Date = .distantPast
    private let qrCooldown: TimeInterval = 2.0

    // Debug: progressive test steps for START QR
    private var testStep = 0
    private var testStepReady = true  // must look away from QR between steps

    private var currentVideoURL: URL?
    private var currentCSVURL: URL?
    private var currentAnchor: SyncAnchor?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func setup() {
        // Forward child ObservableObject changes so SwiftUI re-renders
        cameraManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        motionManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        cameraManager.onQRCodeDetected = { [weak self] value in
            Task { @MainActor in
                self?.handleQRCode(value)
            }
        }
        // Track when QR disappears (no detection for 1.5s = "looked away")
        cameraManager.onQRCodeLost = { [weak self] in
            Task { @MainActor in
                self?.testStepReady = true
                if let step = self?.testStep, step > 0, step < 5 {
                    self?.lastQREvent = "Step \(step) done. Show QR again for step \(step + 1)"
                }
            }
        }

        // Pre-configure audio session so tone playback doesn't interrupt camera
        TonePlayer.shared.configureAudioSession()

        cameraManager.configure()
        loadRecordings()
    }

    private func handleQRCode(_ value: String) {
        guard value.hasPrefix(Self.qrPrefix) else { return }
        let command = String(value.dropFirst(Self.qrPrefix.count)).uppercased()

        // Cooldown to prevent rapid-fire
        let now = Date()
        guard now.timeIntervalSince(lastQRCommandTime) >= qrCooldown else { return }

        switch command {
        case "START":
            guard !isRecording else { return }
            guard testStepReady else { return }  // must look away between steps
            lastQRCommandTime = now
            testStepReady = false
            testStep += 1

            switch testStep {
            case 1:
                lastQREvent = "TEST 1/5: QR detected OK"
            case 2:
                lastQREvent = "TEST 2/5: Playing tone..."
                TonePlayer.shared.playStartTone()
            case 3:
                lastQREvent = "TEST 3/5: Starting IMU..."
                let anchor = motionManager.startRecording()
                currentAnchor = anchor
                // Stop IMU after 1s
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    _ = self.motionManager.stopRecording()
                    self.lastQREvent = "TEST 3/5: IMU OK (\(self.motionManager.sampleCount) samples)"
                }
            case 4:
                lastQREvent = "TEST 4/5: Starting camera recording..."
                let dir = FileManager.recordingsDirectory()
                let testURL = dir.appendingPathComponent("test_debug.mov")
                cameraManager.startRecording(to: testURL)
                // Stop after 1s
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    self.cameraManager.stopRecording()
                    try? FileManager.default.removeItem(at: testURL)
                    self.lastQREvent = "TEST 4/5: Camera record OK"
                }
            default:
                lastQREvent = "TEST 5/5: Full flow..."
                TonePlayer.shared.playStartTone()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !self.isRecording else { return }
                    self.startRecording()
                }
            }

        case "STOP":
            guard isRecording else { return }
            lastQRCommandTime = now
            lastQREvent = "QR: STOP detected"
            stopRecording()
            TonePlayer.shared.playStopTone()
        default:
            break
        }
    }

    func requestPermissions() async -> Bool {
        let videoGranted = await AVCaptureDevice.requestAccess(for: .video)
        let audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
        return videoGranted && audioGranted
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dir = FileManager.recordingsDirectory()
        let videoURL = dir.appendingPathComponent("rec_\(timestamp).mov")
        let csvURL = dir.appendingPathComponent("rec_\(timestamp).csv")

        currentVideoURL = videoURL
        currentCSVURL = csvURL

        // Start IMU first to capture sync anchor
        let anchor = motionManager.startRecording()
        currentAnchor = anchor

        // Start video recording
        cameraManager.startRecording(to: videoURL)

        isRecording = true
        recordingDuration = 0

        // Update duration timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration += 0.1
            }
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil

        // Stop both
        cameraManager.stopRecording()
        let samples = motionManager.stopRecording()
        imuSampleCount = samples.count

        // Write CSV
        if let csvURL = currentCSVURL, let anchor = currentAnchor {
            writeCSV(samples: samples, anchor: anchor, to: csvURL)
        }

        // Create recording entry
        if let videoURL = currentVideoURL, let csvURL = currentCSVURL {
            let recording = Recording(
                date: Date(),
                videoURL: videoURL,
                csvURL: csvURL
            )
            recordings.insert(recording, at: 0)
        }

        isRecording = false
        currentVideoURL = nil
        currentCSVURL = nil
        currentAnchor = nil
    }

    private func writeCSV(samples: [IMUSample], anchor: SyncAnchor, to url: URL) {
        var content = anchor.csvHeader + "\n"
        content += IMUSample.csvColumnHeader + "\n"
        for sample in samples {
            content += sample.csvRow + "\n"
        }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func loadRecordings() {
        let dir = FileManager.recordingsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let movFiles = files.filter { $0.pathExtension == "mov" }
        var loaded: [Recording] = []

        for movURL in movFiles {
            let baseName = movURL.deletingPathExtension().lastPathComponent
            let csvURL = dir.appendingPathComponent("\(baseName).csv")

            guard FileManager.default.fileExists(atPath: csvURL.path) else { continue }

            let attrs = try? FileManager.default.attributesOfItem(atPath: movURL.path)
            let date = attrs?[.creationDate] as? Date ?? Date()

            loaded.append(Recording(date: date, videoURL: movURL, csvURL: csvURL))
        }

        recordings = loaded.sorted { $0.date > $1.date }
    }

    func deleteRecording(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.videoURL)
        try? FileManager.default.removeItem(at: recording.csvURL)
        recordings.removeAll { $0.id == recording.id }
    }
}
