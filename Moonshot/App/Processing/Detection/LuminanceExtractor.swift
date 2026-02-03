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
        if let accelerated = extractAccelerated(from: cgImage) {
            return accelerated
        }
        return extractSlow(from: cgImage)
    }

    private func extractSlow(from cgImage: CGImage) -> LuminanceBuffer? {
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

        guard let luminance = lumaFromARGB8888Buffer(destBuffer, width: dstWidth, height: dstHeight) else {
            return extractSlow(from: cgImage)
        }

        return LuminanceBuffer(width: dstWidth, height: dstHeight, data: luminance)
    }

    /// Extract luminance using vImage (faster for large images)
    func extractAccelerated(from cgImage: CGImage) -> LuminanceBuffer? {
        let width = cgImage.width
        let height = cgImage.height

        // Create format for source
        var sourceFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: Unmanaged.passRetained(CGColorSpaceCreateDeviceRGB()),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )

        // Create source buffer
        var sourceBuffer = vImage_Buffer()
        defer {
            free(sourceBuffer.data)
        }

        var error = vImageBuffer_InitWithCGImage(
            &sourceBuffer,
            &sourceFormat,
            nil,
            cgImage,
            vImage_Flags(kvImageNoFlags)
        )

        guard error == kvImageNoError else {
            return nil
        }

        guard let luma = lumaFromARGB8888Buffer(sourceBuffer, width: width, height: height) else {
            return nil
        }

        return LuminanceBuffer(width: width, height: height, data: luma)
    }

    private func lumaFromARGB8888Buffer(
        _ buffer: vImage_Buffer,
        width: Int,
        height: Int
    ) -> [Float]? {
        let count = width * height
        guard count > 0 else { return nil }

        var a = [Float](repeating: 0, count: count)
        var r = [Float](repeating: 0, count: count)
        var g = [Float](repeating: 0, count: count)
        var b = [Float](repeating: 0, count: count)
        let rowBytes = width * MemoryLayout<Float>.stride

        let maxFloat: [Float] = [1, 1, 1, 1]
        let minFloat: [Float] = [0, 0, 0, 0]

        let convertError: vImage_Error = a.withUnsafeMutableBytes { aPtr in
            r.withUnsafeMutableBytes { rPtr in
                g.withUnsafeMutableBytes { gPtr in
                    b.withUnsafeMutableBytes { bPtr in
                        var aBuffer = vImage_Buffer(
                            data: aPtr.baseAddress!,
                            height: vImagePixelCount(height),
                            width: vImagePixelCount(width),
                            rowBytes: rowBytes
                        )
                        var rBuffer = vImage_Buffer(
                            data: rPtr.baseAddress!,
                            height: vImagePixelCount(height),
                            width: vImagePixelCount(width),
                            rowBytes: rowBytes
                        )
                        var gBuffer = vImage_Buffer(
                            data: gPtr.baseAddress!,
                            height: vImagePixelCount(height),
                            width: vImagePixelCount(width),
                            rowBytes: rowBytes
                        )
                        var bBuffer = vImage_Buffer(
                            data: bPtr.baseAddress!,
                            height: vImagePixelCount(height),
                            width: vImagePixelCount(width),
                            rowBytes: rowBytes
                        )

                        var localBuffer = buffer
                        return vImageConvert_ARGB8888toPlanarF(
                            &localBuffer,
                            &aBuffer,
                            &rBuffer,
                            &gBuffer,
                            &bBuffer,
                            maxFloat,
                            minFloat,
                            vImage_Flags(kvImageNoFlags)
                        )
                    }
                }
            }
        }

        guard convertError == kvImageNoError else { return nil }

        var y = [Float](repeating: 0, count: count)
        var rc: Float = 0.2126
        vDSP_vsmul(r, 1, &rc, &y, 1, vDSP_Length(count))

        var gc: Float = 0.7152
        vDSP_vsma(g, 1, &gc, y, 1, &y, 1, vDSP_Length(count))

        var bc: Float = 0.0722
        vDSP_vsma(b, 1, &bc, y, 1, &y, 1, vDSP_Length(count))

        return y
    }
}
