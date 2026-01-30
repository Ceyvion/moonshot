import Metal
import MetalPerformanceShaders

/// Singleton providing shared Metal resources.
/// All GPU operations go through this context.
final class MetalContext {

    // MARK: - Singleton

    static let shared = MetalContext()

    // MARK: - Core Metal Objects

    /// The Metal device (GPU)
    let device: MTLDevice

    /// Command queue for submitting work to GPU
    let commandQueue: MTLCommandQueue

    /// Default shader library compiled from .metal files
    let library: MTLLibrary

    // MARK: - Initialization

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to load default Metal library. Ensure .metal files are in the target.")
        }

        self.device = device
        self.commandQueue = queue
        self.library = library
    }

    // MARK: - Device Capabilities

    /// Check if the device supports the required features
    var supportsRequiredFeatures: Bool {
        // We need compute shaders and reasonable texture sizes
        return device.supportsFamily(.apple4) // A11 or later
    }

    /// Maximum texture dimension supported
    var maxTextureSize: Int {
        // Most modern iOS devices support 16384
        return 16384
    }

    /// Check if device supports non-uniform threadgroup sizes
    var supportsNonUniformThreadgroups: Bool {
        return device.supportsFamily(.apple4)
    }

    // MARK: - Convenience Methods

    /// Create a new command buffer
    func makeCommandBuffer() -> MTLCommandBuffer? {
        return commandQueue.makeCommandBuffer()
    }

    /// Create a compute command encoder
    func makeComputeEncoder(commandBuffer: MTLCommandBuffer) -> MTLComputeCommandEncoder? {
        return commandBuffer.makeComputeCommandEncoder()
    }

    /// Load a function from the default library
    func loadFunction(named name: String) -> MTLFunction? {
        return library.makeFunction(name: name)
    }

    /// Create a compute pipeline state for a function
    func makePipelineState(function: MTLFunction) throws -> MTLComputePipelineState {
        return try device.makeComputePipelineState(function: function)
    }

    /// Create a compute pipeline state by function name
    func makePipelineState(functionName: String) throws -> MTLComputePipelineState {
        guard let function = loadFunction(named: functionName) else {
            throw MetalError.functionNotFound(functionName)
        }
        return try makePipelineState(function: function)
    }
}

// MARK: - Metal Errors

enum MetalError: LocalizedError {
    case functionNotFound(String)
    case pipelineCreationFailed(String)
    case commandBufferCreationFailed
    case encoderCreationFailed
    case textureCreationFailed
    case bufferCreationFailed
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .functionNotFound(let name):
            return "Metal function '\(name)' not found in library"
        case .pipelineCreationFailed(let reason):
            return "Failed to create pipeline: \(reason)"
        case .commandBufferCreationFailed:
            return "Failed to create command buffer"
        case .encoderCreationFailed:
            return "Failed to create command encoder"
        case .textureCreationFailed:
            return "Failed to create texture"
        case .bufferCreationFailed:
            return "Failed to create buffer"
        case .executionFailed(let reason):
            return "GPU execution failed: \(reason)"
        }
    }
}
