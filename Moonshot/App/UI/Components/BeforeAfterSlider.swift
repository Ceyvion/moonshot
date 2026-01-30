import SwiftUI
import UIKit

/// Interactive before/after comparison slider.
struct BeforeAfterSlider: View {
    let before: UIImage
    let after: UIImage
    @Binding var position: CGFloat

    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // After image (full width)
                Image(uiImage: after)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Before image (clipped to slider position)
                Image(uiImage: before)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(
                        HorizontalClipShape(position: position)
                    )

                // Slider line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .position(x: geometry.size.width * position, y: geometry.size.height / 2)
                    .shadow(color: .black.opacity(0.5), radius: 2)

                // Slider handle
                sliderHandle
                    .position(x: geometry.size.width * position, y: geometry.size.height / 2)

                // Labels
                labelsOverlay
            }
            .gesture(
                DragGesture()
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        let newPosition = value.location.x / geometry.size.width
                        position = min(max(newPosition, 0.05), 0.95)
                    }
            )
            .contentShape(Rectangle())
        }
    }

    // MARK: - Slider Handle

    private var sliderHandle: some View {
        ZStack {
            // Outer circle
            Circle()
                .fill(Color.white)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.3), radius: 4)

            // Inner arrows
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(.black)
        }
        .scaleEffect(isDragging ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }

    // MARK: - Labels

    private var labelsOverlay: some View {
        VStack {
            HStack {
                Text("Original")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer()

                Text("Enhanced")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding()

            Spacer()
        }
    }
}

// MARK: - Clip Shape

struct HorizontalClipShape: Shape {
    let position: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(
            x: 0,
            y: 0,
            width: rect.width * position,
            height: rect.height
        ))
        return path
    }
}

#Preview {
    BeforeAfterSlider(
        before: UIImage(systemName: "moon")!,
        after: UIImage(systemName: "moon.fill")!,
        position: .constant(0.5)
    )
    .frame(height: 400)
    .background(Color.black)
}
