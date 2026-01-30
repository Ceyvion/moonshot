import CoreGraphics
import Foundation

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
}
