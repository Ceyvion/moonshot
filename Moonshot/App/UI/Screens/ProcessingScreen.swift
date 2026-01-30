import SwiftUI
import UIKit

/// Screen showing processing progress for video stacking.
struct ProcessingScreen: View {
    let source: AppCoordinator.ProcessingSource

    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var viewModel = ProcessingViewModel()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Moon icon with animation
            moonAnimation

            // Progress info
            progressSection

            Spacer()

            // Cancel button
            Button("Cancel") {
                viewModel.cancel()
                coordinator.goBack()
            }
            .foregroundColor(.gray)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 32)
        .background(Color.black)
        .navigationBarBackButtonHidden(true)
        .task {
            await viewModel.process(source: source)

            if let result = viewModel.result {
                coordinator.navigateTo(.result(
                    enhanced: ImagePayload(image: result.enhanced),
                    original: ImagePayload(image: result.original),
                    parameters: result.parameters
                ))
            }
        }
    }

    // MARK: - Moon Animation

    private var moonAnimation: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.1), .clear],
                        center: .center,
                        startRadius: 50,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)

            // Constellation progress (morphing stars)
            ConstellationProgress(progress: viewModel.progress)
                .animation(.easeInOut(duration: 0.6), value: viewModel.progress)

            // Moon (centered)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white, .gray],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 70, height: 70)
                .shadow(color: .white.opacity(0.3), radius: 15, x: 0, y: 0)
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 16) {
            Text(viewModel.currentStage)
                .font(.headline)
                .foregroundColor(.white)

            if !viewModel.stageDetail.isEmpty {
                Text(viewModel.stageDetail)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            // Frame count for video
            if case .video = source, viewModel.frameCount > 0 {
                Text("\(viewModel.framesProcessed) / \(viewModel.frameCount) frames")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - View Model

@MainActor
final class ProcessingViewModel: ObservableObject {
    struct ProcessingResult {
        let enhanced: UIImage
        let original: UIImage
        let parameters: ProcessingParameters
    }

    @Published var progress: Double = 0
    @Published var currentStage: String = "Preparing..."
    @Published var stageDetail: String = ""
    @Published var frameCount: Int = 0
    @Published var framesProcessed: Int = 0
    @Published var result: ProcessingResult?

    private var isCancelled = false

    func process(source: AppCoordinator.ProcessingSource) async {
        switch source {
        case .photo(let payload):
            await processPhoto(payload.image)
        case .video(let payload):
            await processVideo(payload.url)
        }
    }

    func cancel() {
        isCancelled = true
    }

    private func processPhoto(_ image: UIImage) async {
        guard !isCancelled else { return }

        currentStage = "Detecting moon..."
        stageDetail = ""
        progress = 0.05

        do {
            let detection = try await Task.detached(priority: .userInitiated) { () async throws -> MoonDetectionResult? in
                let detector = MoonDetector()
                guard let cgImage = image.cgImage else { return nil }
                return try await detector.detectFast(in: cgImage, targetWidth: 512)
            }.value
            guard let detection, detection.confidence.circleConfidence >= 0.5 else {
                currentStage = "Moon not detected"
                stageDetail = "Try a tighter crop or use a still photo"
                progress = 1.0
                return
            }

            guard let cgImage = image.cgImage else {
                currentStage = "Unable to read image"
                progress = 1.0
                return
            }

            let output = try await Task.detached(priority: .userInitiated) { () async throws -> EnhancementPipeline.Output in
                let pipeline = EnhancementPipeline()
                let input = EnhancementPipeline.Input(
                    cgImage: cgImage,
                    detection: detection,
                    preset: .natural,
                    strength: 50,
                    isVideo: false
                )

                return try pipeline.run(input) { stage, pipelineProgress in
                    Task { @MainActor in
                        self.currentStage = stage
                        self.stageDetail = ""
                        self.progress = max(self.progress, pipelineProgress)
                    }
                }
            }.value

            progress = 1.0
            result = ProcessingResult(
                enhanced: UIImage(cgImage: output.enhanced),
                original: UIImage(cgImage: output.originalCrop),
                parameters: ProcessingParameters(preset: .natural, strength: 50)
            )
        } catch {
            currentStage = "Enhancement failed"
            stageDetail = "Please try again"
            progress = 1.0
        }
    }

    private func processVideo(_ url: URL) async {
        guard !isCancelled else { return }

        _ = url
        currentStage = "Video stacking coming soon"
        stageDetail = "Still-photo enhancement is available now."
        progress = 1.0
    }
}

#Preview {
    NavigationStack {
        ProcessingScreen(source: .video(VideoPayload(url: URL(fileURLWithPath: "/tmp/test.mov"))))
            .environmentObject(AppCoordinator())
    }
}
