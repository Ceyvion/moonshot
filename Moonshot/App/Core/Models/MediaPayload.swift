import Foundation
import UIKit

/// Wrapper for image payloads with stable identity for navigation.
struct ImagePayload: Hashable {
    let id: UUID
    let image: UIImage

    init(id: UUID = UUID(), image: UIImage) {
        self.id = id
        self.image = image
    }

    static func == (lhs: ImagePayload, rhs: ImagePayload) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Wrapper for video payloads with stable identity for navigation.
struct VideoPayload: Hashable {
    let id: UUID
    let url: URL

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }

    static func == (lhs: VideoPayload, rhs: VideoPayload) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
