import Foundation

#if canImport(NaturalLanguage)
import NaturalLanguage
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

    public static func l2Normalized(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(Float(0)) { $0 + ($1 * $1) })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}
