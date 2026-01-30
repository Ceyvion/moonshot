import SwiftUI

@main
struct MoonshotApp: App {
    @StateObject private var coordinator = AppCoordinator()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main app content
                NavigationStack(path: $coordinator.navigationPath) {
                    HomeScreen()
                        .navigationDestination(for: AppCoordinator.Route.self) { route in
                            destinationView(for: route)
                        }
                }
                .environmentObject(coordinator)
                .opacity(showSplash ? 0 : 1)

                // Splash screen overlay
                if showSplash {
                    SplashScreenView(isPresented: $showSplash)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
    }

    @ViewBuilder
    private func destinationView(for route: AppCoordinator.Route) -> some View {
        switch route {
        case .enhancePhoto(let payload):
            EnhanceScreen(image: payload.image)
        case .captureForDetail:
            CaptureScreen()
        case .processing(let source):
            ProcessingScreen(source: source)
        case .result(let enhanced, let original, let parameters):
            ResultScreen(enhanced: enhanced.image, original: original.image, parameters: parameters)
        }
    }
}
