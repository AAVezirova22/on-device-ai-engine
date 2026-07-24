import Foundation
import EdgeAINativeKernels

#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

#if canImport(Metal)
import Metal
#endif

public protocol EmbeddingModel {
    var identifier: String { get }
    var dimensions: Int { get }
    func embed(_ text: String) -> [Float]
}

public struct HashEmbeddingModel: EmbeddingModel {
    public let identifier = "hash"
    public let dimensions: Int

    public init(dimensions: Int = 384) {
        precondition(dimensions > 16, "Use enough dimensions to reduce hash collisions.")
        self.dimensions = dimensions
    }

    public func embed(_ text: String) -> [Float] {
        var vector = Array(repeating: Float(0), count: dimensions)
        let tokens = Tokenizer.tokens(in: text)

        for token in tokens {
            let hash = StableHash.fnv1a64(token)
            let index = Int(hash % UInt64(dimensions))
            let sign: Float = ((hash >> 63) == 0) ? 1 : -1
            vector[index] += sign
        }

        return VectorMath.l2Normalized(vector)
    }
}

public final class NaturalLanguageEmbeddingModel: EmbeddingModel {
    public let identifier = "natural"
    public let dimensions: Int

    #if canImport(NaturalLanguage)
    private let sentenceEmbedding: NLEmbedding?
    private let wordEmbedding: NLEmbedding?
    #endif

    public init() throws {
        #if canImport(NaturalLanguage)
        self.sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
        self.wordEmbedding = NLEmbedding.wordEmbedding(for: .english)

        if let sentenceEmbedding {
            self.dimensions = Int(sentenceEmbedding.dimension)
        } else if let wordEmbedding {
            self.dimensions = Int(wordEmbedding.dimension)
        } else {
            throw EmbeddingModelError.unavailable("Apple NaturalLanguage English embeddings are unavailable on this system.")
        }
        #else
        throw EmbeddingModelError.unavailable("NaturalLanguage framework is unavailable on this platform.")
        #endif
    }

    public func embed(_ text: String) -> [Float] {
        #if canImport(NaturalLanguage)
        if let sentenceVector = sentenceEmbedding?.vector(for: text) {
            return VectorMath.l2Normalized(sentenceVector.map(Float.init))
        }

        guard let wordEmbedding else {
            return Array(repeating: 0, count: dimensions)
        }

        var sum = Array(repeating: Float(0), count: dimensions)
        var count: Float = 0

        for token in Tokenizer.tokens(in: text) {
            guard let vector = wordEmbedding.vector(for: token), vector.count == dimensions else {
                continue
            }

            for index in vector.indices {
                sum[index] += Float(vector[index])
            }
            count += 1
        }

        guard count > 0 else {
            return Array(repeating: 0, count: dimensions)
        }

        return VectorMath.l2Normalized(sum.map { $0 / count })
        #else
        return Array(repeating: 0, count: dimensions)
        #endif
    }
}

public enum EmbeddingModelError: Error, CustomStringConvertible {
    case unavailable(String)
    case unsupported(String)
    case dimensionMismatch(expected: Int, actual: Int, model: String)

    public var description: String {
        switch self {
        case .unavailable(let message):
            return message
        case .unsupported(let model):
            return "Unsupported embedding model: \(model). Supported values: hash, natural."
        case .dimensionMismatch(let expected, let actual, let model):
            return "Embedding model \(model) has \(actual) dimensions, but the index expects \(expected)."
        }
    }
}

public enum EmbeddingModelFactory {
    public static func make(identifier: String, dimensions: Int? = nil) throws -> EmbeddingModel {
        switch normalized(identifier) {
        case "hash":
            return HashEmbeddingModel(dimensions: dimensions ?? 384)
        case "natural", "naturallanguage", "apple-nl", "apple-natural-language":
            let model = try NaturalLanguageEmbeddingModel()
            if let dimensions, dimensions != model.dimensions {
                throw EmbeddingModelError.dimensionMismatch(
                    expected: dimensions,
                    actual: model.dimensions,
                    model: model.identifier
                )
            }
            return model
        default:
            throw EmbeddingModelError.unsupported(identifier)
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Tokenizer {
    static func tokens(in text: String) -> [String] {
        text.lowercased()
            .split { character in
                !(character.isLetter || character.isNumber)
            }
            .map(String.init)
            .filter { $0.count > 1 }
    }
}

enum StableHash {
    static func fnv1a64(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }

        return hash
    }

    static func hexFNV1A64(_ value: String) -> String {
        String(format: "%016llx", fnv1a64(value))
    }
}

public enum VectorMath {
    public static func dot(_ left: [Float], _ right: [Float]) -> Float {
        precondition(left.count == right.count, "Vectors must have the same dimensionality.")
        var sum: Float = 0
        for index in left.indices {
            sum += left[index] * right[index]
        }
        return sum
    }

    public static func dot(
        _ left: [Float],
        _ right: [Float],
        backend: VectorScoringBackend
    ) -> Float {
        switch backend {
        case .swift:
            return dot(left, right)
        case .nativeCxx:
            return NativeVectorKernels.dot(left, right)
        case .metal:
            return MetalVectorScorer.shared?.dot(left, right) ?? dot(left, right)
        case .auto:
            if let metalScore = MetalVectorScorer.shared?.dot(left, right) {
                return metalScore
            }
            return NativeVectorKernels.dot(left, right)
        }
    }

    public static func l2Normalized(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(Float(0)) { $0 + ($1 * $1) })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}

public enum NativeVectorKernels {
    public static func dot(_ left: [Float], _ right: [Float]) -> Float {
        precondition(left.count == right.count, "Vectors must have the same dimensionality.")
        guard !left.isEmpty else { return 0 }

        return left.withUnsafeBufferPointer { leftPointer in
            right.withUnsafeBufferPointer { rightPointer in
                edgeai_dot_product_f32(
                    leftPointer.baseAddress,
                    rightPointer.baseAddress,
                    Int32(left.count)
                )
            }
        }
    }
}

public final class MetalVectorScorer {
    public static let shared = MetalVectorScorer()

    #if canImport(Metal)
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    #endif

    private init?() {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        let shader = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void edgeai_dot_product(
            device const float *left [[buffer(0)]],
            device const float *right [[buffer(1)]],
            device float *partial [[buffer(2)]],
            constant uint &count [[buffer(3)]],
            uint id [[thread_position_in_grid]]
        ) {
            if (id < count) {
                partial[id] = left[id] * right[id];
            }
        }
        """

        guard let library = try? device.makeLibrary(source: shader, options: nil),
              let function = library.makeFunction(name: "edgeai_dot_product"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = pipeline
        #else
        return nil
        #endif
    }

    public func dot(_ left: [Float], _ right: [Float]) -> Float? {
        precondition(left.count == right.count, "Vectors must have the same dimensionality.")
        guard !left.isEmpty else { return 0 }

        #if canImport(Metal)
        let byteCount = left.count * MemoryLayout<Float>.stride
        guard let leftBuffer = left.withUnsafeBufferPointer({ pointer in
            pointer.baseAddress.map {
                device.makeBuffer(bytes: $0, length: byteCount, options: .storageModeShared)
            } ?? nil
        }),
              let rightBuffer = right.withUnsafeBufferPointer({ pointer in
                  pointer.baseAddress.map {
                      device.makeBuffer(bytes: $0, length: byteCount, options: .storageModeShared)
                  } ?? nil
              }),
              let partialBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared),
              var count = UInt32(exactly: left.count),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(leftBuffer, offset: 0, index: 0)
        encoder.setBuffer(rightBuffer, offset: 0, index: 1)
        encoder.setBuffer(partialBuffer, offset: 0, index: 2)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 3)

        let threads = MTLSize(width: left.count, height: 1, depth: 1)
        let threadgroupWidth = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        let threadgroup = MTLSize(width: threadgroupWidth, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: threadgroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard commandBuffer.error == nil else {
            return nil
        }

        let partials = partialBuffer.contents().bindMemory(to: Float.self, capacity: left.count)
        return UnsafeBufferPointer(start: partials, count: left.count).reduce(Float(0), +)
        #else
        return nil
        #endif
    }
}
