import Foundation

/// Estimates sharpness using Laplacian variance inside the moon mask.
final class SharpnessScorer {
    private let normalization: Float = 0.02

    func score(luma: [Float], width: Int, height: Int, mask: MaskBuffer) -> Float {
        guard width > 2, height > 2 else { return 0 }
        guard mask.width == width, mask.height == height else { return 0 }

        var sum: Float = 0
        var sumSq: Float = 0
        var count: Int = 0

        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let idx = row + x
                if mask.data[idx] < 0.5 {
                    continue
                }

                let center = luma[idx]
                let laplacian = -4 * center
                    + luma[idx - 1]
                    + luma[idx + 1]
                    + luma[idx - width]
                    + luma[idx + width]

                sum += laplacian
                sumSq += laplacian * laplacian
                count += 1
            }
        }

        guard count > 0 else { return 0 }

        let mean = sum / Float(count)
        let variance = max(0, sumSq / Float(count) - mean * mean)
        let normalized = min(1, variance / normalization)
        return normalized
    }
}
