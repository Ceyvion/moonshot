import SwiftUI

/// Animated splash screen with morphing constellation and falling stars displayed on app launch
struct SplashScreenView: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Binding var isPresented: Bool
    @State private var moonPulse = false

    var body: some View {
        ZStack {
            // Star field background (only if motion is not reduced)
            if !reduceMotion {
                SnowView()
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }

            // Content overlay
            VStack(spacing: 24) {
                // Moon with morphing constellation
                ZStack {
                    // Morphing constellation around the moon
                    AnimatedConstellation()

                    // Moon icon centered within constellation
                    Image(systemName: "moon.fill")
                        .font(.system(size: 70))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(white: 0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .white.opacity(0.5), radius: 25, x: 0, y: 0)
                        .scaleEffect(reduceMotion ? 1.0 : (moonPulse ? 1.02 : 0.98))
                }

                // App title
                Text("Moonshot")
                    .font(.system(size: 56, weight: .light, design: .serif))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    moonPulse = true
                }
            }
            // Auto-dismiss after 3.5 seconds (slightly longer to show constellation morph)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                let animation = reduceMotion ? nil : Animation.easeInOut(duration: 0.5)
                withAnimation(animation) { isPresented = false }
            }
        }
        .onChange(of: reduceMotion) { newValue in
            if newValue {
                moonPulse = false
            } else {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    moonPulse = true
                }
            }
        }
    }
}

#Preview {
    SplashScreenView(isPresented: .constant(true))
}
