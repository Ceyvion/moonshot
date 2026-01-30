import Metal
import MetalPerformanceShaders

/// Executes Metal compute pipelines with caching and convenience methods.
final class MetalRunner {

    // MARK: - Properties

    private let context: MetalContext
    private var pipelineCache: [String: MTLComputePipelineState] = [:]
    private let cacheQueue = DispatchQueue(label: "com.moonshot.pipelineCache")

    // MARK: - Initialization

    init(context: MetalContext = .shared) {
        self.context = context
    }

    // MARK: - Pipeline Management

    /// Get or create a pipeline state for a function name.
    /// Pipelines are cached for reuse.
    func pipeline(named functionName: String) throws -> MTLComputePipelineState {
        // Check cache first
        if let cached = cacheQueue.sync(execute: { pipelineCache[functionName] }) {
            return cached
        }

        // Create new pipeline
        let pipeline = try context.makePipelineState(functionName: functionName)

        // Cache it
        cacheQueue.sync {
            pipelineCache[functionName] = pipeline
        }

        return pipeline
    }

    /// Clear the pipeline cache (useful for memory pressure)
    func clearCache() {
        cacheQueue.sync {
            pipelineCache.removeAll()
        }
    }

    // MARK: - Execution

    /// Execute a compute pipeline synchronously.
    /// - Parameters:
    ///   - pipeline: The compute pipeline to execute
    ///   - textures: Textures to bind (in order)
    ///   - buffers: Buffers with their indices
    ///   - gridSize: Total number of threads needed (usually texture dimensions)
    func execute(
        pipeline: MTLComputePipelineState,
        textures: [MTLTexture],
        buffers: [(buffer: MTLBuffer, index: Int)] = [],
        gridSize: MTLSize
    ) throws {
        guard let commandBuffer = context.makeCommandBuffer() else {
            throw MetalError.commandBufferCreationFailed
        }

        guard let encoder = context.makeComputeEncoder(commandBuffer: commandBuffer) else {
            throw MetalError.encoderCreationFailed
        }

        encoder.setComputePipelineState(pipeline)

        // Bind textures
        for (index, texture) in textures.enumerated() {
            encoder.setTexture(texture, index: index)
        }

        // Bind buffers
        for (buffer, index) in buffers {
            encoder.setBuffer(buffer, offset: 0, index: index)
        }

        // Calculate threadgroup size
        let threadgroupSize = calculateThreadgroupSize(for: pipeline, gridSize: gridSize)

        // Dispatch
        if context.supportsNonUniformThreadgroups {
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        } else {
            let threadgroupCount = MTLSize(
                width: (gridSize.width + threadgroupSize.width - 1) / threadgroupSize.width,
                height: (gridSize.height + threadgroupSize.height - 1) / threadgroupSize.height,
                depth: (gridSize.depth + threadgroupSize.depth - 1) / threadgroupSize.depth
            )
            encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        }

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw MetalError.executionFailed(error.localizedDescription)
        }
    }

    /// Execute a compute pipeline asynchronously.
    func executeAsync(
        pipeline: MTLComputePipelineState,
        textures: [MTLTexture],
        buffers: [(buffer: MTLBuffer, index: Int)] = [],
        gridSize: MTLSize
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let commandBuffer = context.makeCommandBuffer() else {
                continuation.resume(throwing: MetalError.commandBufferCreationFailed)
                return
            }

            guard let encoder = context.makeComputeEncoder(commandBuffer: commandBuffer) else {
                continuation.resume(throwing: MetalError.encoderCreationFailed)
                return
            }

            encoder.setComputePipelineState(pipeline)

            for (index, texture) in textures.enumerated() {
                encoder.setTexture(texture, index: index)
            }

            for (buffer, index) in buffers {
                encoder.setBuffer(buffer, offset: 0, index: index)
            }

            let threadgroupSize = calculateThreadgroupSize(for: pipeline, gridSize: gridSize)

            if context.supportsNonUniformThreadgroups {
                encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
            } else {
                let threadgroupCount = MTLSize(
                    width: (gridSize.width + threadgroupSize.width - 1) / threadgroupSize.width,
                    height: (gridSize.height + threadgroupSize.height - 1) / threadgroupSize.height,
                    depth: (gridSize.depth + threadgroupSize.depth - 1) / threadgroupSize.depth
                )
                encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            }

            encoder.endEncoding()

            commandBuffer.addCompletedHandler { buffer in
                if let error = buffer.error {
                    continuation.resume(throwing: MetalError.executionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }

            commandBuffer.commit()
        }
    }

    /// Execute by function name (convenience method)
    func execute(
        functionName: String,
        textures: [MTLTexture],
        buffers: [(buffer: MTLBuffer, index: Int)] = [],
        gridSize: MTLSize
    ) throws {
        let pipeline = try self.pipeline(named: functionName)
        try execute(pipeline: pipeline, textures: textures, buffers: buffers, gridSize: gridSize)
    }

    // MARK: - Helpers

    /// Calculate optimal threadgroup size for a pipeline
    private func calculateThreadgroupSize(for pipeline: MTLComputePipelineState, gridSize: MTLSize) -> MTLSize {
        let maxTotalThreads = pipeline.maxTotalThreadsPerThreadgroup
        let threadExecutionWidth = pipeline.threadExecutionWidth

        // For 2D images, use square-ish threadgroups
        if gridSize.depth == 1 {
            let width = threadExecutionWidth
            let height = maxTotalThreads / width
            return MTLSize(width: width, height: min(height, 16), depth: 1)
        }

        // For 3D, divide evenly
        let side = Int(cbrt(Double(maxTotalThreads)))
        return MTLSize(width: side, height: side, depth: side)
    }
}

// MARK: - Buffer Creation Helpers

extension MetalRunner {

    /// Create a buffer with initial data (T must be a trivial/POD type).
    func makeBuffer<T>(from data: [T]) -> MTLBuffer? {
        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            return context.device.makeBuffer(
                bytes: baseAddress,
                length: rawBuffer.count,
                options: .storageModeShared
            )
        }
    }

    /// Create a buffer for a single value (T must be a trivial/POD type).
    func makeBuffer<T>(from value: T) -> MTLBuffer? {
        var mutableValue = value
        return withUnsafeBytes(of: &mutableValue) { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            return context.device.makeBuffer(
                bytes: baseAddress,
                length: rawBuffer.count,
                options: .storageModeShared
            )
        }
    }

    /// Create an empty buffer of specified size
    func makeBuffer(length: Int) -> MTLBuffer? {
        return context.device.makeBuffer(length: length, options: .storageModeShared)
    }
}
