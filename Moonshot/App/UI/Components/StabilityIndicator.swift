import SwiftUI

/// Visual indicator of hand stability during capture.
struct StabilityIndicator: View {
    let stability: Float  // 0.0 to 1.0

    var body: some View {
        HStack(spacing: 6) {
            // Icon
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundColor(stabilityColor)

            // Bars
            HStack(spacing: 2) {
                ForEach(0..<4) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(for: index))
                        .frame(width: 4, height: barHeight(for: index))
                }
            }
            .frame(height: 16)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var iconName: String {
        if stability > 0.8 {
            return "hand.raised.fill"
        } else if stability > 0.4 {
            return "hand.raised"
        } else {
            return "waveform"
        }
    }

    private var stabilityColor: Color {
        if stability > 0.8 {
            return .green
        } else if stability > 0.4 {
            return .yellow
        } else {
            return .orange
        }
    }

    private func barColor(for index: Int) -> Color {
        let threshold = Float(index + 1) * 0.25
        return stability >= threshold ? stabilityColor : .white.opacity(0.3)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 6
        let increment: CGFloat = 3
        return baseHeight + CGFloat(index) * increment
    }
}

#Preview {
    VStack(spacing: 16) {
        StabilityIndicator(stability: 0.1)
        StabilityIndicator(stability: 0.3)
        StabilityIndicator(stability: 0.5)
        StabilityIndicator(stability: 0.7)
        StabilityIndicator(stability: 0.9)
        StabilityIndicator(stability: 1.0)
    }
    .padding()
    .background(Color.black)
}
