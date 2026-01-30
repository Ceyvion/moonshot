import SwiftUI

/// Animated splash screen with falling snow effect displayed on app launch
struct SplashScreenView: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Binding var isPresented: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Snow effect background (only if motion is not reduced)
            if !reduceMotion {
                SnowView()
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }

            // Content overlay
            VStack(spacing: 20) {
                // Moon icon with glow effect (matching HomeScreen)
                Image(systemName: "moon.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(white: 0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .white.opacity(0.4), radius: 30, x: 0, y: 0)
                    .scaleEffect(reduceMotion ? 1.0 : (pulse ? 1.03 : 0.97))

                // App title
                Text("Moonshot")
                    .font(.system(size: 56, weight: .light, design: .serif))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            // Auto-dismiss after 2.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                let animation = reduceMotion ? nil : Animation.easeInOut(duration: 0.5)
                withAnimation(animation) { isPresented = false }
            }
        }
        .onChange(of: reduceMotion) { newValue in
            if newValue {
                pulse = false
            } else {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}

#Preview {
    SplashScreenView(isPresented: .constant(true))
}
