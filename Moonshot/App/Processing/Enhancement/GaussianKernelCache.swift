import Foundation

/// Caches Gaussian kernels to avoid recomputation across stages.
final class GaussianKernelCache {
    static let shared = GaussianKernelCache()

    private var cache: [Int: [Float]] = [:]
    private let queue = DispatchQueue(label: "com.moonshot.gaussianKernelCache")

    func kernel(sigma: Float) -> [Float] {
        let clampedSigma = max(0.1, sigma)
        let key = Int(round(clampedSigma * 1000))
        if let cached = queue.sync(execute: { cache[key] }) {
            return cached
        }

        let kernel = GaussianKernelCache.buildKernel(sigma: clampedSigma)
        queue.sync {
            cache[key] = kernel
        }
        return kernel
    }

    private static func buildKernel(sigma: Float) -> [Float] {
        let radius = max(1, Int(ceil(3 * Double(sigma))))
        let size = radius * 2 + 1
        var kernel = [Float](repeating: 0, count: size)

        let sigma2 = 2 * sigma * sigma
        var sum: Float = 0
        for i in -radius...radius {
            let x = Float(i)
            let value = exp(-(x * x) / sigma2)
            kernel[i + radius] = value
            sum += value
        }

        if sum > 0 {
            for i in 0..<kernel.count {
                kernel[i] /= sum
            }
        }

        return kernel
    }
}
