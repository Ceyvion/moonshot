import Metal
import CoreVideo
import CoreImage
import UIKit
import Accelerate

/// Manages Metal texture creation, conversion, and caching.
final class TextureManager {

    // MARK: - Properties

    private let device: MTLDevice
    private var textureCache: CVMetalTextureCache?

    // MARK: - Initialization

    init(device: MTLDevice = MetalContext.shared.device) {
        self.device = device
        setupTextureCache()
    }

    private func setupTextureCache() {
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )

        if status == kCVReturnSuccess {
            textureCache = cache
        }
    }

    // MARK: - Texture Creation

    /// Create an empty texture with specified dimensions and format
    func createTexture(
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat = .rgba16Float,
        usage: MTLTextureUsage = [.shaderRead, .shaderWrite]
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .private

        return device.makeTexture(descriptor: descriptor)
    }

    /// Create a texture that can be read back to CPU
    func createReadableTexture(
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat = .rgba16Float
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared

        return device.makeTexture(descriptor: descriptor)
    }

    /// Create a single-channel (luminance) texture
    func createLuminanceTexture(width: Int, height: Int) -> MTLTexture? {
        return createTexture(
            width: width,
            height: height,
            pixelFormat: .r16Float,
            usage: [.shaderRead, .shaderWrite]
        )
    }

    // MARK: - CGImage Conversion

    /// Create a texture from a CGImage
    func createTexture(from cgImage: CGImage) -> MTLTexture? {
        let width = cgImage.width
        let height = cgImage.height

        // Create descriptor
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        // Copy image data to texture
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )

        texture.replace(region: region, mipmapLevel: 0, withBytes: rawData, bytesPerRow: bytesPerRow)

        return texture
    }

    /// Create a texture from UIImage
    func createTexture(from uiImage: UIImage) -> MTLTexture? {
        guard let cgImage = uiImage.cgImage else { return nil }
        return createTexture(from: cgImage)
    }

    // MARK: - CVPixelBuffer Conversion

    /// Create a texture from CVPixelBuffer (zero-copy when possible)
    func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else {
            return createTextureCopy(from: pixelBuffer)
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTex = cvTexture else {
            return createTextureCopy(from: pixelBuffer)
        }

        return CVMetalTextureGetTexture(cvTex)
    }

    /// Create a texture by copying pixel buffer data (fallback)
    private func createTextureCopy(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let texture = createTexture(
            width: width,
            height: height,
            pixelFormat: .bgra8Unorm,
            usage: [.shaderRead, .shaderWrite]
        ) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )

        texture.replace(region: region, mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: bytesPerRow)

        return texture
    }

    // MARK: - Texture to Image Conversion

    /// Convert texture to CGImage
    func createCGImage(from texture: MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height

        // Handle different pixel formats
        switch texture.pixelFormat {
        case .rgba8Unorm, .bgra8Unorm:
            return createCGImageFrom8BitTexture(texture, width: width, height: height)
        case .rgba16Float, .r16Float:
            return createCGImageFrom16BitTexture(texture, width: width, height: height)
        default:
            return nil
        }
    }

    private func createCGImageFrom8BitTexture(_ texture: MTLTexture, width: Int, height: Int) -> CGImage? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)

        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )

        texture.getBytes(&rawData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        // Swap BGRA to RGBA if needed
        if texture.pixelFormat == .bgra8Unorm {
            for i in stride(from: 0, to: rawData.count, by: 4) {
                let temp = rawData[i]
                rawData[i] = rawData[i + 2]
                rawData[i + 2] = temp
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        return context.makeImage()
    }

    private func createCGImageFrom16BitTexture(_ texture: MTLTexture, width: Int, height: Int) -> CGImage? {
        // For 16-bit float textures, we need to convert to 8-bit for display
        let channels = texture.pixelFormat == .r16Float ? 1 : 4
        let bytesPerPixel = channels * 2  // 16-bit = 2 bytes per channel
        let bytesPerRow = width * bytesPerPixel
        var rawData = [Float16](repeating: 0, count: height * width * channels)

        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )

        texture.getBytes(&rawData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        // Convert to 8-bit RGBA
        var outputData = [UInt8](repeating: 255, count: width * height * 4)

        for i in 0..<(width * height) {
            if channels == 1 {
                // Grayscale to RGB
                let value = UInt8(clamping: Int(Float(rawData[i]) * 255))
                outputData[i * 4] = value
                outputData[i * 4 + 1] = value
                outputData[i * 4 + 2] = value
                outputData[i * 4 + 3] = 255
            } else {
                // RGBA
                outputData[i * 4] = UInt8(clamping: Int(Float(rawData[i * 4]) * 255))
                outputData[i * 4 + 1] = UInt8(clamping: Int(Float(rawData[i * 4 + 1]) * 255))
                outputData[i * 4 + 2] = UInt8(clamping: Int(Float(rawData[i * 4 + 2]) * 255))
                outputData[i * 4 + 3] = UInt8(clamping: Int(Float(rawData[i * 4 + 3]) * 255))
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let outputBytesPerRow = width * 4

        guard let context = CGContext(
            data: &outputData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: outputBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        return context.makeImage()
    }

    /// Convert texture to UIImage
    func createUIImage(from texture: MTLTexture) -> UIImage? {
        guard let cgImage = createCGImage(from: texture) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Texture Cache Management

    /// Flush the texture cache (call periodically or on memory warning)
    func flushCache() {
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }
}

// MARK: - Texture Copying

extension TextureManager {

    /// Copy one texture to another using blit encoder
    func copy(from source: MTLTexture, to destination: MTLTexture) throws {
        guard let commandBuffer = MetalContext.shared.makeCommandBuffer() else {
            throw MetalError.commandBufferCreationFailed
        }

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw MetalError.encoderCreationFailed
        }

        let sourceSize = MTLSize(width: source.width, height: source.height, depth: 1)

        blitEncoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: sourceSize,
            to: destination,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )

        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// Create a copy of a texture
    func duplicate(_ texture: MTLTexture) -> MTLTexture? {
        guard let copy = createTexture(
            width: texture.width,
            height: texture.height,
            pixelFormat: texture.pixelFormat,
            usage: texture.usage
        ) else {
            return nil
        }

        try? self.copy(from: texture, to: copy)
        return copy
    }
}
