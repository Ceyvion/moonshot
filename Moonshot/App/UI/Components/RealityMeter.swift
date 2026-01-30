import SwiftUI

/// Visual indicator of capture quality (Low/Medium/High).
/// Sets user expectations about enhancement results.
struct RealityMeter: View {
    let quality: CaptureQuality
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            if !compact {
                Text("Capture Quality")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Quality bars
            HStack(spacing: 2) {
                ForEach(0..<3) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor(for: index))
                        .frame(
                            width: compact ? 8 : 12,
                            height: compact ? 16 : 20
                        )
                }
            }

            // Label
            Text(quality.displayName)
                .font(.caption.weight(.medium))
                .foregroundColor(quality.displayColor)
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 4 : 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fillColor(for index: Int) -> Color {
        let threshold: Int
        switch quality {
        case .low: threshold = 1
        case .medium: threshold = 2
        case .high: threshold = 3
        }
        return index < threshold ? quality.displayColor : Color(.tertiarySystemFill)
    }
}

// MARK: - CaptureQuality Color Extension

extension CaptureQuality {
    var displayColor: Color {
        switch self {
        case .low: return .orange
        case .medium: return .yellow
        case .high: return .green
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        RealityMeter(quality: .low)
        RealityMeter(quality: .medium)
        RealityMeter(quality: .high)

        Divider()

        HStack(spacing: 16) {
            RealityMeter(quality: .low, compact: true)
            RealityMeter(quality: .medium, compact: true)
            RealityMeter(quality: .high, compact: true)
        }
    }
    .padding()
    .background(Color(.systemBackground))
}
