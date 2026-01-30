import SwiftUI

/// Toggle between Natural and Crisp presets.
struct PresetToggle: View {
    @Binding var preset: EnhancementPreset

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EnhancementPreset.allCases, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        preset = option
                    }
                } label: {
                    Text(option.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(preset == option ? .black : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            preset == option
                                ? Color.white
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    VStack(spacing: 20) {
        PresetToggle(preset: .constant(.natural))
        PresetToggle(preset: .constant(.crisp))
    }
    .padding()
    .background(Color(.systemBackground))
}
