import SwiftUI
import UIKit

/// Screen for one-tap photo enhancement.
/// Shows detection progress, moon preview, and enhancement controls.
struct EnhanceScreen: View {
    let image: UIImage

    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var viewModel: EnhanceViewModel

    init(image: UIImage) {
        self.image = image
        self._viewModel = StateObject(wrappedValue: EnhanceViewModel(image: image))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            ZStack {
                Color.black

                switch viewModel.state {
                case .detecting:
                    detectingView

                case .detected:
                    detectedView

                case .failed(let reason):
                    failedView(reason: reason)

                case .processing:
                    processingView
                }
            }

            // Controls (only when detected)
            if case .detected = viewModel.state {
                controlsPanel
            }
        }
        .navigationTitle("Enhance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if case .detected = viewModel.state {
                    Button("Process") {
                        viewModel.startProcessing()
                    }
                }
            }
        }
        .task {
            await viewModel.detectMoon()
        }
        .onChange(of: viewModel.processingComplete) { complete in
            if complete, let result = viewModel.enhancedImage {
                coordinator.navigateTo(.result(
                    enhanced: ImagePayload(image: result),
                    original: ImagePayload(image: viewModel.croppedOriginal ?? image),
                    parameters: viewModel.currentParameters
                ))
            }
        }
    }

    // MARK: - State Views

    private var detectingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Detecting moon...")
                .font(.headline)
                .foregroundColor(.white)
        }
    }

    private var detectedView: some View {
        VStack(spacing: 0) {
            // Moon preview
            if let preview = viewModel.previewImage {
                Image(uiImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }

            // Quality indicator
            if let quality = viewModel.captureQuality {
                RealityMeter(quality: quality)
                    .padding(.bottom, 16)
            }
        }
    }

    private func failedView(reason: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "moon.fill")
                .font(.system(size: 64))
                .foregroundColor(.gray)

            Text("Could not detect moon")
                .font(.headline)
                .foregroundColor(.white)

            Text(reason)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Choose Different Photo") {
                coordinator.goBack()
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    private var processingView: some View {
        VStack(spacing: 24) {
            ProgressView(value: viewModel.processingProgress)
                .tint(.white)
                .frame(width: 200)

            Text("Enhancing...")
                .font(.headline)
                .foregroundColor(.white)

            Text(viewModel.processingStage)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    // MARK: - Controls Panel

    private var controlsPanel: some View {
        VStack(spacing: 16) {
            // Preset toggle
            PresetToggle(preset: $viewModel.selectedPreset)

            // Strength slider
            StrengthSlider(value: $viewModel.strength)

            // Warnings
            ForEach(viewModel.warnings, id: \.self) { warning in
                WarningBanner(message: warning)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - View Model

@MainActor
final class EnhanceViewModel: ObservableObject {
    enum State {
        case detecting
        case detected
        case failed(String)
        case processing
    }

    @Published var state: State = .detecting
    @Published var previewImage: UIImage?
    @Published var croppedOriginal: UIImage?
    @Published var captureQuality: CaptureQuality?
    @Published var selectedPreset: EnhancementPreset = .natural
    @Published var strength: Float = 50
    @Published var warnings: [String] = []
    @Published var processingProgress: Double = 0
    @Published var processingStage: String = ""
    @Published var processingComplete = false
    @Published var enhancedImage: UIImage?

    private let image: UIImage
    private var detectionResult: MoonDetectionResult?

    var currentParameters: ProcessingParameters {
        ProcessingParameters(preset: selectedPreset, strength: strength)
    }

    init(image: UIImage) {
        self.image = image
    }

    func detectMoon() async {
        state = .detecting

        warnings = []

        do {
            let image = self.image
            let result = try await Task.detached(priority: .userInitiated) { () async throws -> MoonDetectionResult? in
                let detector = MoonDetector()
                guard let cgImage = image.cgImage else { return nil }
                return try await detector.detectFast(in: cgImage, targetWidth: 512)
            }.value

            guard let detection = result,
                  detection.confidence.circleConfidence >= 0.5 else {
                state = .failed("Moon not confidently detected. Try a tighter crop or video mode.")
                return
            }

            guard let cgImage = image.cgImage,
                  let cropped = ImageCropper.crop(cgImage: cgImage, rect: detection.cropRect) else {
                state = .failed("Unable to crop the moon region.")
                return
            }

            let conversion = ColorConverter.rgbToYCbCrFloat(cropped)
            guard conversion.width > 0, conversion.height > 0 else {
                state = .failed("Unable to analyze the moon crop.")
                return
            }
            let luma = conversion.y

            let moonMask = detection.moonMask.resized(toWidth: conversion.width, height: conversion.height)
            let limbRing = detection.limbRingMask.resized(toWidth: conversion.width, height: conversion.height)

            let confidence = ConfidenceMapBuilder().build(
                luma: luma,
                width: conversion.width,
                height: conversion.height,
                moonMask: moonMask,
                limbRing: limbRing
            )

            let sharpness = SharpnessScorer().score(
                luma: luma,
                width: conversion.width,
                height: conversion.height,
                mask: moonMask
            )

            captureQuality = CaptureQuality.from(
                medianConfidence: confidence.medianC,
                clippedFraction: detection.clippedHighlightFraction,
                sharpnessScore: sharpness
            )

            if detection.clippedHighlightFraction > 0.003 {
                warnings.append("Highlights clipped. Kept the result natural.")
            }

            previewImage = UIImage(cgImage: cropped)
            croppedOriginal = UIImage(cgImage: cropped)
            detectionResult = detection
            state = .detected
        } catch {
            state = .failed("Moon detection failed. Please try a different photo.")
        }
    }

    func startProcessing() {
        state = .processing
        processingProgress = 0
        processingStage = "Preparing..."
        processingComplete = false
        enhancedImage = nil

        guard let detection = detectionResult,
              let cgImage = image.cgImage else {
            state = .failed("Missing detection data. Please try again.")
            return
        }

        let preset = selectedPreset
        let strength = self.strength

        Task.detached(priority: .userInitiated) {
            do {
                let pipeline = EnhancementPipeline()
                let input = EnhancementPipeline.Input(
                    cgImage: cgImage,
                    detection: detection,
                    preset: preset,
                    strength: strength,
                    isVideo: false
                )

                let output = try pipeline.run(input) { stage, progress in
                    Task { @MainActor in
                        self.processingStage = stage
                        self.processingProgress = progress
                    }
                }

                await MainActor.run {
                    self.enhancedImage = UIImage(cgImage: output.enhanced)
                    self.warnings = output.warnings
                    self.processingComplete = true
                }
            } catch {
                await MainActor.run {
                    self.state = .failed("Enhancement failed. Please try again.")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        EnhanceScreen(image: UIImage(systemName: "moon.fill")!)
            .environmentObject(AppCoordinator())
    }
}
