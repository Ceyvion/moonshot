import SwiftUI
import UIKit

/// Central navigation coordinator for Moonshot.
/// Manages navigation state and routes between screens.
@MainActor
final class AppCoordinator: ObservableObject {

    // MARK: - Route Definition

    enum Route: Hashable {
        case enhancePhoto(image: ImagePayload)
        case captureForDetail
        case processing(source: ProcessingSource)
        case result(enhanced: ImagePayload, original: ImagePayload, parameters: ProcessingParameters)
    }

    /// Source of frames for processing
    enum ProcessingSource: Hashable {
        case photo(ImagePayload)
        case video(VideoPayload)
    }

    // MARK: - Published State

    @Published var navigationPath = NavigationPath()
    @Published var presentedSheet: SheetType?
    @Published var alertMessage: AlertMessage?

    // MARK: - Sheet Types

    enum SheetType: Identifiable {
        case photoPicker
        case settings

        var id: String {
            switch self {
            case .photoPicker: return "photoPicker"
            case .settings: return "settings"
            }
        }
    }

    // MARK: - Alert

    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    // MARK: - Navigation Methods

    func navigateTo(_ route: Route) {
        navigationPath.append(route)
    }

    func goBack() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    func goToRoot() {
        navigationPath = NavigationPath()
    }

    func presentSheet(_ sheet: SheetType) {
        presentedSheet = sheet
    }

    func dismissSheet() {
        presentedSheet = nil
    }

    func showAlert(title: String, message: String) {
        alertMessage = AlertMessage(title: title, message: message)
    }
}
