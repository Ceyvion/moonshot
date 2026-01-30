import SwiftUI

/// Slider for controlling enhancement strength (0-100).
struct StrengthSlider: View {
    @Binding var value: Float

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("Strength")
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(Int(value))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            // Slider
            Slider(value: $value, in: 0...100, step: 1)
                .tint(.primary)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StrengthSlider(value: .constant(0))
        StrengthSlider(value: .constant(50))
        StrengthSlider(value: .constant(100))
    }
    .padding()
    .background(Color(.systemBackground))
}
