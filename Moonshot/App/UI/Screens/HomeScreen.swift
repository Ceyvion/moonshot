import SwiftUI
import PhotosUI
import UIKit

/// Home screen with two main actions: Enhance Photo and Capture for Detail.
struct HomeScreen: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Title area
            titleSection

            Spacer()

            // Action buttons
            actionSection

            Spacer()

            // Footer
            footerSection
        }
        .padding(.horizontal, 32)
        .background(Color.black)
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { newItem in
            Task {
                await loadSelectedPhoto(newItem)
            }
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        VStack(spacing: 20) {
            // Moon icon with glow effect
            Image(systemName: "moon.fill")
                .font(.system(size: 72))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(white: 0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .white.opacity(0.3), radius: 20, x: 0, y: 0)

            // App title
            Text("Moonshot")
                .font(.system(size: 48, weight: .light, design: .serif))
                .foregroundColor(.white)

            // Tagline - benefit focused
            Text("Reveal the moon your eyes actually saw")
                .font(.subheadline)
                .foregroundColor(Color(white: 0.6))
        }
    }

    private var actionSection: some View {
        VStack(spacing: 16) {
            // Primary: Enhance Photo button
            Button {
                showPhotoPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 18, weight: .medium))
                    Text("Enhance a Photo")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [.white, Color(white: 0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .white.opacity(0.15), radius: 12, x: 0, y: 4)
            }

            // Secondary: Capture for Detail button
            Button {
                coordinator.navigateTo(.captureForDetail)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 18, weight: .medium))
                    Text("Capture New Detail")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }

            // Hint text - explains the benefit
            Text("Video mode stacks multiple frames to reveal detail invisible in a single shot")
                .font(.caption)
                .foregroundColor(Color(white: 0.5))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 8)
        }
    }

    private var footerSection: some View {
        VStack(spacing: 6) {
            Text("100% real. Zero AI generation.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(white: 0.45))

            Text("We only enhance what your camera actually captured.")
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.35))
        }
        .padding(.bottom, 40)
    }

    // MARK: - Photo Loading

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }

        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                await MainActor.run {
                    coordinator.navigateTo(.enhancePhoto(image: ImagePayload(image: uiImage)))
                    selectedPhotoItem = nil
                }
            }
        } catch {
            await MainActor.run {
                coordinator.showAlert(
                    title: "Unable to Load Photo",
                    message: "Please try selecting a different photo."
                )
                selectedPhotoItem = nil
            }
        }
    }
}

#Preview {
    HomeScreen()
        .environmentObject(AppCoordinator())
}
