import Foundation
import CoreGraphics
import Accelerate

/// Buffer holding luminance data
struct LuminanceBuffer {
    let width: Int
    let height: Int
    let data: [Float]

    func value(at x: Int, y: Int) -> Float {
        guard x >= 0 && x < width && y >= 0 && y < height else { return 0 }
        return data[y * width + x]
    }

    /// Get percentile value
    func percentile(_ p: Float) -> Float {
        let sorted = data.sorted()
        let index = Int(Float(sorted.count - 1) * p)
        return sorted[index]
    }

    /// Calculate mean within a circular region
    func meanInCircle(center: CGPoint, radius: CGFloat) -> Float {
        var sum: Float = 0
        var count = 0

        let centerX = Int(center.x)
        let centerY = Int(center.y)
        let radiusInt = Int(radius)

        for y in max(0, centerY - radiusInt)..<min(height, centerY + radiusInt) {
            for x in max(0, centerX - radiusInt)..<min(width, centerX + radiusInt) {
                let dx = Float(x - centerX)
                let dy = Float(y - centerY)
                if sqrt(dx * dx + dy * dy) <= Float(radius) {
                    sum += value(at: x, y: y)
                    count += 1
                }
            }
        }

        return count > 0 ? sum / Float(count) : 0
    }

    /// Calculate standard deviation within a circular region
    func stdInCircle(center: CGPoint, radius: CGFloat) -> Float {
        let mean = meanInCircle(center: center, radius: radius)
        var sumSq: Float = 0
        var count = 0

        let centerX = Int(center.x)
        let centerY = Int(center.y)
        let radiusInt = Int(radius)

        for y in max(0, centerY - radiusInt)..<min(height, centerY + radiusInt) {
            for x in max(0, centerX - radiusInt)..<min(width, centerX + radiusInt) {
                let dx = Float(x - centerX)
                let dy = Float(y - centerY)
                if sqrt(dx * dx + dy * dy) <= Float(radius) {
                    let diff = value(at: x, y: y) - mean
                    sumSq += diff * diff
                    count += 1
                }
            }
        }

        return count > 1 ? sqrt(sumSq / Float(count - 1)) : 0
    }
}

/// Extracts luminance channel from images
final class LuminanceExtractor {

    /// Extract luminance from CGImage
    func extract(from cgImage: CGImage) -> LuminanceBuffer? {
        let width = cgImage.width
        let height = cgImage.height

        // Get pixel data
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return nil
        }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        var luminance = [Float](repeating: 0, count: width * height)

        // BT.709 coefficients
        let rCoeff: Float = 0.2126
        let gCoeff: Float = 0.7152
        let bCoeff: Float = 0.0722

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel

                // Handle different pixel formats
                let r: Float
                let g: Float
                let b: Float

                if cgImage.bitmapInfo.contains(.byteOrder32Little) {
                    // BGRA format
                    b = Float(ptr[offset]) / 255.0
                    g = Float(ptr[offset + 1]) / 255.0
                    r = Float(ptr[offset + 2]) / 255.0
                } else {
                    // RGBA format
                    r = Float(ptr[offset]) / 255.0
                    g = Float(ptr[offset + 1]) / 255.0
                    b = Float(ptr[offset + 2]) / 255.0
                }

                luminance[y * width + x] = r * rCoeff + g * gCoeff + b * bCoeff
            }
        }

        return LuminanceBuffer(width: width, height: height, data: luminance)
    }

    /// Extract downsampled luminance using vImage for fast detection.
    func extractDownsampled(from cgImage: CGImage, targetWidth: Int) -> LuminanceBuffer? {
        guard targetWidth > 0 else { return nil }
        let srcWidth = cgImage.width
        let srcHeight = cgImage.height

        if targetWidth >= srcWidth {
            return extract(from: cgImage)
        }

        let scale = min(1.0, Float(targetWidth) / Float(srcWidth))
        let dstWidth = max(1, Int(round(Float(srcWidth) * scale)))
        let dstHeight = max(1, Int(round(Float(srcHeight) * scale)))

        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: Unmanaged.passRetained(CGColorSpaceCreateDeviceRGB()),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )

        var sourceBuffer = vImage_Buffer()
        let initError = vImageBuffer_InitWithCGImage(
            &sourceBuffer,
            &format,
            nil,
            cgImage,
            vImage_Flags(kvImageNoFlags)
        )

        guard initError == kvImageNoError else {
            return extract(from: cgImage)
        }
        defer {
            if let data = sourceBuffer.data {
                free(data)
            }
        }

        var destBuffer = vImage_Buffer()
        destBuffer.width = vImagePixelCount(dstWidth)
        destBuffer.height = vImagePixelCount(dstHeight)
        destBuffer.rowBytes = dstWidth * 4
        destBuffer.data = UnsafeMutableRawPointer.allocate(
            byteCount: destBuffer.rowBytes * dstHeight,
            alignment: MemoryLayout<UInt8>.alignment
        )
        defer {
            destBuffer.data?.deallocate()
        }

        let scaleError = vImageScale_ARGB8888(
            &sourceBuffer,
            &destBuffer,
            nil,
            vImage_Flags(kvImageHighQualityResampling)
        )

        guard scaleError == kvImageNoError else {
            return extract(from: cgImage)
        }

        let pixelPtr = destBuffer.data!.assumingMemoryBound(to: UInt8.self)
        var luminance = [Float](repeating: 0, count: dstWidth * dstHeight)

        let rCoeff: Float = 0.2126
        let gCoeff: Float = 0.7152
        let bCoeff: Float = 0.0722

        for y in 0..<dstHeight {
            let rowStart = y * destBuffer.rowBytes
            let outRow = y * dstWidth
            for x in 0..<dstWidth {
                let offset = rowStart + x * 4
                let r = Float(pixelPtr[offset + 1]) / 255.0
                let g = Float(pixelPtr[offset + 2]) / 255.0
                let b = Float(pixelPtr[offset + 3]) / 255.0
                luminance[outRow + x] = r * rCoeff + g * gCoeff + b * bCoeff
            }
        }

        return LuminanceBuffer(width: dstWidth, height: dstHeight, data: luminance)
    }

    /// Extract luminance using vImage (faster for large images)
    func extractAccelerated(from cgImage: CGImage) -> LuminanceBuffer? {
        let width = cgImage.width
        let height = cgImage.height

        // Create format for source
        guard var sourceFormat = vImage_CGImageFormat(cgImage: cgImage) else {
            return extract(from: cgImage)  // Fallback
        }

        // Create source buffer
        var sourceBuffer = vImage_Buffer()
        defer {
            sourceBuffer.data?.deallocate()
        }

        var error = vImageBuffer_InitWithCGImage(
            &sourceBuffer,
            &sourceFormat,
            nil,
            cgImage,
            vImage_Flags(kvImageNoFlags)
        )

        guard error == kvImageNoError else {
            return extract(from: cgImage)
        }

        // Create destination buffer (planar float)
        var destBuffer = vImage_Buffer()
        destBuffer.width = vImagePixelCount(width)
        destBuffer.height = vImagePixelCount(height)
        destBuffer.rowBytes = width * MemoryLayout<Float>.stride

        let destData = UnsafeMutablePointer<Float>.allocate(capacity: width * height)
        destBuffer.data = UnsafeMutableRawPointer(destData)

        defer {
            destBuffer.data?.deallocate()
        }

        // Convert to planar float (we'll compute luminance manually)
        // This is a simplified approach; full implementation would use vImageMatrixMultiply

        // For now, use the non-accelerated path
        return extract(from: cgImage)
    }
}
