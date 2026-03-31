import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = RecordingViewModel()
    @State private var showRecordings = false
    @State private var permissionsGranted = false
    @State private var recordButtonScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: viewModel.cameraManager.captureSession)
                .ignoresSafeArea()

            // Gradient overlays for readability
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 200)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top Status Bar
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer()

                // MARK: - Recording Info
                if viewModel.isRecording {
                    recordingInfoPanel
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .padding(.bottom, 20)
                }

                // MARK: - Lens Selector
                if viewModel.cameraManager.availableCameras.count > 1 {
                    lensPicker
                        .padding(.bottom, 24)
                }

                // MARK: - Record Button
                recordButton
                    .padding(.bottom, 16)

                // MARK: - Bottom Label
                Text(viewModel.isRecording ? "Recording" : "Ready")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 32)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isRecording)
        .task {
            permissionsGranted = await viewModel.requestPermissions()
            if permissionsGranted {
                viewModel.setup()
            }
        }
        .sheet(isPresented: $showRecordings) {
            RecordingsListView(viewModel: viewModel)
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Duration badge
            if viewModel.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: .red.opacity(0.6), radius: 4)
                    Text(formatDuration(viewModel.recordingDuration))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            // Recordings folder
            Button {
                showRecordings = true
            } label: {
                Image(systemName: "square.stack.3d.down.right.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .disabled(viewModel.isRecording)
            .opacity(viewModel.isRecording ? 0.4 : 1.0)
        }
    }

    // MARK: - Recording Info Panel

    private var recordingInfoPanel: some View {
        HStack(spacing: 20) {
            infoItem(icon: "sensor.fill", label: "IMU", value: "\(viewModel.motionManager.sampleCount)")
            divider
            infoItem(icon: "camera.fill", label: "Lens", value: cameraShortName)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 40)
    }

    private func infoItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 28)
    }

    // MARK: - Lens Picker

    private var lensPicker: some View {
        HStack(spacing: 4) {
            ForEach(Array(viewModel.cameraManager.availableCameras.enumerated()), id: \.offset) { index, _ in
                let isSelected = index == viewModel.cameraManager.currentCameraIndex
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.cameraManager.switchCamera(to: index)
                    }
                } label: {
                    Text(lensLabel(for: index))
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .yellow : .white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .background(
                            isSelected
                                ? AnyShapeStyle(.white.opacity(0.2))
                                : AnyShapeStyle(.clear)
                            , in: Circle()
                        )
                }
                .disabled(viewModel.isRecording)
                .opacity(viewModel.isRecording ? 0.4 : 1.0)
            }
        }
        .padding(4)
        .background(.black.opacity(0.3), in: Capsule())
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            viewModel.toggleRecording()
        } label: {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)

                // Inner shape
                if viewModel.isRecording {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.red)
                        .frame(width: 30, height: 30)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 64, height: 64)
                }
            }
            .scaleEffect(recordButtonScale)
        }
        .pressAction(
            onPress: { withAnimation(.easeInOut(duration: 0.1)) { recordButtonScale = 0.9 } },
            onRelease: { withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { recordButtonScale = 1.0 } }
        )
    }

    // MARK: - Helpers

    private var cameraShortName: String {
        guard !viewModel.cameraManager.availableCameras.isEmpty else { return "--" }
        return lensLabel(for: viewModel.cameraManager.currentCameraIndex)
    }

    private func lensLabel(for index: Int) -> String {
        guard index < viewModel.cameraManager.availableCameras.count else { return "?" }
        let device = viewModel.cameraManager.availableCameras[index]
        switch device.deviceType {
        case .builtInUltraWideCamera: return "0.5"
        case .builtInWideAngleCamera: return "1x"
        case .builtInTelephotoCamera: return "3x"
        default: return "?"
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int(duration * 10) % 10
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Press Gesture Modifier

struct PressActionModifier: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded { _ in onRelease() }
            )
    }
}

extension View {
    func pressAction(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressActionModifier(onPress: onPress, onRelease: onRelease))
    }
}
