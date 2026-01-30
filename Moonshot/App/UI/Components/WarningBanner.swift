import SwiftUI

/// Warning banner for issues like clipped highlights.
struct WarningBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.subheadline)

            Text(message)
                .font(.caption)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    VStack(spacing: 12) {
        WarningBanner(message: "Highlights clipped. Kept the result natural.")
        WarningBanner(message: "Low capture quality. Consider using video mode.")
        WarningBanner(message: "Halo mitigation applied.")
    }
    .padding()
    .background(Color(.systemBackground))
}
