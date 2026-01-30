import CoreGraphics

/// Crops CGImages to a specified rect with bounds clamping.
enum ImageCropper {
    static func crop(cgImage: CGImage, rect: CGRect) -> CGImage? {
        guard let cropRect = clampedRect(for: cgImage, rect: rect) else { return nil }
        return cgImage.cropping(to: cropRect)
    }

    static func clampedRect(for cgImage: CGImage, rect: CGRect) -> CGRect? {
        let originX = max(0, Int(rect.origin.x.rounded(.down)))
        let originY = max(0, Int(rect.origin.y.rounded(.down)))
        let width = min(cgImage.width - originX, Int(rect.width.rounded(.down)))
        let height = min(cgImage.height - originY, Int(rect.height.rounded(.down)))

        guard width > 0, height > 0 else { return nil }

        return CGRect(x: originX, y: originY, width: width, height: height)
    }
}
