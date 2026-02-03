import CoreGraphics
import Foundation
import Accelerate

/// Color space conversions for enhancement pipeline.
enum ColorConverter {
    // BT.709 coefficients
    private static let rCoeff: Float = 0.2126
    private static let gCoeff: Float = 0.7152
    private static let bCoeff: Float = 0.0722

    private static let cbDenom: Float = 1.8556
    private static let crDenom: Float = 1.5748

    static func rgbToYCbCrFloat(_ cgImage: CGImage) -> (y: [Float], cb: [Float], cr: [Float], width: Int, height: Int) {
        let width = cgImage.width
        let height = cgImage.height

        guard width > 0, height > 0 else {
            return ([], [], [], 0, 0)
        }

        if let accelerated = rgbToYCbCrAccelerated(cgImage: cgImage) {
            return accelerated
        }

        return rgbToYCbCrSlow(cgImage: cgImage)
    }

    private static func rgbToYCbCrAccelerated(
        cgImage: CGImage
    ) -> (y: [Float], cb: [Float], cr: [Float], width: Int, height: Int)? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

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

        guard initError == kvImageNoError else { return nil }
        defer {
            free(sourceBuffer.data)
        }

        let count = width * height
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

                        return vImageConvert_ARGB8888toPlanarF(
                            &sourceBuffer,
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
        var rc = rCoeff
        vDSP_vsmul(r, 1, &rc, &y, 1, vDSP_Length(count))

        var gc = gCoeff
        vDSP_vsma(g, 1, &gc, y, 1, &y, 1, vDSP_Length(count))

        var bc = bCoeff
        vDSP_vsma(b, 1, &bc, y, 1, &y, 1, vDSP_Length(count))

        var cb = [Float](repeating: 0, count: count)
        vDSP_vsub(y, 1, b, 1, &cb, 1, vDSP_Length(count))
        var cbDiv = cbDenom
        vDSP_vsdiv(cb, 1, &cbDiv, &cb, 1, vDSP_Length(count))

        var cr = [Float](repeating: 0, count: count)
        vDSP_vsub(y, 1, r, 1, &cr, 1, vDSP_Length(count))
        var crDiv = crDenom
        vDSP_vsdiv(cr, 1, &crDiv, &cr, 1, vDSP_Length(count))

        return (y, cb, cr, width, height)
    }

    static func yCbCrToCGImage(y: [Float], cb: [Float], cr: [Float], width: Int, height: Int) -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height * 4)

        for row in 0..<height {
            for col in 0..<width {
                let index = row * width + col
                let luma = y[index]
                let cbVal = cb[index]
                let crVal = cr[index]

                var r = luma + crVal * crDenom
                var b = luma + cbVal * cbDenom
                var g = (luma - rCoeff * r - bCoeff * b) / gCoeff

                r = min(1, max(0, r))
                g = min(1, max(0, g))
                b = min(1, max(0, b))

                let outOffset = index * 4
                data[outOffset] = UInt8(r * 255)
                data[outOffset + 1] = UInt8(g * 255)
                data[outOffset + 2] = UInt8(b * 255)
                data[outOffset + 3] = 255
            }
        }

        let cfData = data.withUnsafeBytes { rawBuffer -> CFData in
            let ptr = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
            return CFDataCreate(nil, ptr, data.count)!
        }

        let provider = CGDataProvider(data: cfData)!
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }

    private static func rgbToYCbCrSlow(
        cgImage: CGImage
    ) -> (y: [Float], cb: [Float], cr: [Float], width: Int, height: Int) {
        let width = cgImage.width
        let height = cgImage.height

        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return ([], [], [], 0, 0)
        }

        let bytesPerPixel = max(3, cgImage.bitsPerPixel / 8)
        let bytesPerRow = cgImage.bytesPerRow

        var y = [Float](repeating: 0, count: width * height)
        var cb = [Float](repeating: 0, count: width * height)
        var cr = [Float](repeating: 0, count: width * height)

        let isBGRA = cgImage.bitmapInfo.contains(.byteOrder32Little)

        for row in 0..<height {
            for col in 0..<width {
                let offset = row * bytesPerRow + col * bytesPerPixel

                let r: Float
                let g: Float
                let b: Float

                if isBGRA {
                    b = Float(ptr[offset]) / 255.0
                    g = Float(ptr[offset + 1]) / 255.0
                    r = Float(ptr[offset + 2]) / 255.0
                } else {
                    r = Float(ptr[offset]) / 255.0
                    g = Float(ptr[offset + 1]) / 255.0
                    b = Float(ptr[offset + 2]) / 255.0
                }

                let luma = r * rCoeff + g * gCoeff + b * bCoeff
                let cbVal = (b - luma) / cbDenom
                let crVal = (r - luma) / crDenom

                let index = row * width + col
                y[index] = luma
                cb[index] = cbVal
                cr[index] = crVal
            }
        }

        return (y, cb, cr, width, height)
    }
}
