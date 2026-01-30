import SwiftUI
import AVFoundation

/// Screen for capturing video of the moon for multi-frame stacking.
struct CaptureScreen: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var viewModel = CaptureViewModel()

    var body: some View {
        ZStack {
            // Camera preview background
            Color.black.ignoresSafeArea()

            // Camera preview layer (placeholder)
            cameraPreview

            // Overlay UI
            VStack {
                // Top bar: status and stability
                topBar

                Spacer()

                // Center: targeting guide
                if !viewModel.isLocked {
                    targetingGuide
                }

                Spacer()

                // Bottom: instructions and record button
                bottomControls
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.startCamera()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
        .onChange(of: viewModel.recordedVideoURL) { url in
            if let url = url {
                coordinator.navigateTo(.processing(source: .video(VideoPayload(url: url))))
            }
        }
    }

    // MARK: - Camera Preview

    private var cameraPreview: some View {
        GeometryReader { geometry in
            ZStack {
                // Placeholder for camera preview
                // Will be replaced with actual AVCaptureVideoPreviewLayer
                Rectangle()
                    .fill(Color.black)

                if viewModel.isCameraReady {
                    // Show detection overlay when camera is ready
                    if let moonRect = viewModel.detectedMoonRect {
                        Circle()
                            .stroke(viewModel.isLocked ? Color.green : Color.orange, lineWidth: 2)
                            .frame(
                                width: moonRect.width * geometry.size.width,
                                height: moonRect.height * geometry.size.height
                            )
                            .position(
                                x: moonRect.midX * geometry.size.width,
                                y: moonRect.midY * geometry.size.height
                            )
                    }
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Detection status
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isLocked ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)

                Text(viewModel.isLocked ? "Locked" : "Searching...")
                    .font(.caption)
                    .foregroundColor(.white)
            }

            Spacer()

            // Stability meter
            if viewModel.isDetected {
                StabilityIndicator(stability: viewModel.stability)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Targeting Guide

    private var targetingGuide: some View {
        VStack(spacing: 16) {
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                .frame(width: 200, height: 200)

            Text("Point at the moon")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Instructions
            Text(instructionText)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Recording indicator
            if viewModel.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)

                    Text(String(format: "%.1fs", viewModel.recordingDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white)
                }
            }

            // Record button
            Button {
                if viewModel.isRecording {
                    viewModel.stopRecording()
                } else {
                    viewModel.startRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)

                    if viewModel.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red)
                            .frame(width: 28, height: 28)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 56, height: 56)
                    }
                }
            }
            .disabled(!viewModel.isLocked)
            .opacity(viewModel.isLocked ? 1 : 0.5)
        }
        .padding(.bottom, 40)
    }

    private var instructionText: String {
        if viewModel.isRecording {
            return "Recording... hold steady"
        } else if viewModel.isLocked {
            return "Hold steady and record for 1-3 seconds"
        } else {
            return "Point at the moon to lock exposure"
        }
    }
}

// MARK: - View Model

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var isCameraReady = false
    @Published var isDetected = false
    @Published var isLocked = false
    @Published var stability: Float = 0
    @Published var detectedMoonRect: CGRect?
    @Published var isRecording = false
    @Published var recordingDuration: Double = 0
    @Published var recordedVideoURL: URL?

    private var recordingTimer: Timer?

    func startCamera() async {
        // Simulate camera startup
        try? await Task.sleep(nanoseconds: 500_000_000)
        isCameraReady = true

        // Simulate moon detection after a moment
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isDetected = true
        detectedMoonRect = CGRect(x: 0.35, y: 0.3, width: 0.3, height: 0.3)

        // Simulate stability improving
        for i in 1...5 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            stability = Float(i) * 0.2
        }

        // Lock when stable
        isLocked = true
    }

    func stopCamera() {
        isCameraReady = false
        recordingTimer?.invalidate()
    }

    func startRecording() {
        guard isLocked else { return }

        isRecording = true
        recordingDuration = 0

        // Start timer to track duration
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration += 0.1

                // Auto-stop at 3 seconds
                if self?.recordingDuration ?? 0 >= 3.0 {
                    self?.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false

        // Simulate saving video
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        // For now, just signal completion
        // Real implementation will save the actual video
        recordedVideoURL = tempURL
    }
}

#Preview {
    NavigationStack {
        CaptureScreen()
            .environmentObject(AppCoordinator())
    }
}
