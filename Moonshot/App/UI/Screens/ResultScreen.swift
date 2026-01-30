import SwiftUI
import UIKit

/// Screen showing enhancement result with before/after comparison.
struct ResultScreen: View {
    let enhanced: UIImage
    let original: UIImage
    let parameters: ProcessingParameters

    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var sliderPosition: CGFloat = 0.5
    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Before/after comparison
            BeforeAfterSlider(
                before: original,
                after: enhanced,
                position: $sliderPosition
            )
            .frame(maxHeight: .infinity)

            // Controls panel
            controlsPanel
        }
        .background(Color.black)
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    coordinator.goToRoot()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(image: enhanced)
        }
    }

    // MARK: - Controls Panel

    private var controlsPanel: some View {
        VStack(spacing: 16) {
            // Quality info
            HStack {
                Text("Enhanced with \(parameters.preset.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Spacer()

                Text("\(Int(parameters.strength))% strength")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Divider()

            // Action buttons
            HStack(spacing: 16) {
                Button {
                    coordinator.goToRoot()
                } label: {
                    Label("New Photo", systemImage: "plus")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        ResultScreen(
            enhanced: UIImage(systemName: "moon.fill")!,
            original: UIImage(systemName: "moon")!,
            parameters: ProcessingParameters(preset: .natural, strength: 50)
        )
        .environmentObject(AppCoordinator())
    }
}
