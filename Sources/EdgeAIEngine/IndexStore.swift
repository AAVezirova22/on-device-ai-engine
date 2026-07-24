import Foundation

public struct IndexManifest: Codable, Equatable {
    public let schemaVersion: Int
    public let createdAt: Date
    public let engineVersion: String
    public let embeddingModel: String
    public let embeddingDimensions: Int
    public let documentCount: Int
    public let chunkCount: Int
    public let totalContentBytes: Int
    public let chunking: ChunkingConfiguration
    public let buildMetrics: IndexBuildMetrics?
    public let sourceDocuments: [SourceDocumentMetadata]

    public init(
        schemaVersion: Int = EngineVersion.indexSchemaVersion,
        createdAt: Date = Date(),
        engineVersion: String = EngineVersion.current,
        embeddingModel: String,
        embeddingDimensions: Int,
        documentCount: Int,
        chunkCount: Int,
        totalContentBytes: Int,
        chunking: ChunkingConfiguration,
        buildMetrics: IndexBuildMetrics? = nil,
        sourceDocuments: [SourceDocumentMetadata] = []
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.engineVersion = engineVersion
        self.embeddingModel = embeddingModel
        self.embeddingDimensions = embeddingDimensions
        self.documentCount = documentCount
        self.chunkCount = chunkCount
        self.totalContentBytes = totalContentBytes
        self.chunking = chunking
        self.buildMetrics = buildMetrics
        self.sourceDocuments = sourceDocuments
    }
}

public struct StoredIndex: Codable, Equatable {
    public let manifest: IndexManifest
    public let index: VectorIndex

    public init(manifest: IndexManifest, index: VectorIndex) {
        self.manifest = manifest
        self.index = index
    }
}

public enum IndexStore {
    public static func validate(_ storedIndex: StoredIndex) throws {
        guard storedIndex.manifest.schemaVersion == EngineVersion.indexSchemaVersion else {
            throw IndexStoreError.unsupportedSchema(
                found: storedIndex.manifest.schemaVersion,
                supported: EngineVersion.indexSchemaVersion
            )
        }

        guard storedIndex.manifest.embeddingDimensions == storedIndex.index.embeddingDimensions else {
            throw IndexStoreError.dimensionMismatch(
                manifest: storedIndex.manifest.embeddingDimensions,
                index: storedIndex.index.embeddingDimensions
            )
        }

        guard storedIndex.manifest.chunkCount == storedIndex.index.count else {
            throw IndexStoreError.chunkCountMismatch(
                manifest: storedIndex.manifest.chunkCount,
                index: storedIndex.index.count
            )
        }
    }

    public static func save(_ storedIndex: StoredIndex, to url: URL) throws {
        try validate(storedIndex)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(storedIndex)
        try data.write(to: url, options: [.atomic])
    }

    public static func load(from url: URL) throws -> StoredIndex {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let storedIndex = try decoder.decode(StoredIndex.self, from: data)
        try validate(storedIndex)
        return storedIndex
    }
}

public enum IndexStoreError: Error, CustomStringConvertible {
    case unsupportedSchema(found: Int, supported: Int)
    case dimensionMismatch(manifest: Int, index: Int)
    case chunkCountMismatch(manifest: Int, index: Int)

    public var description: String {
        switch self {
        case .unsupportedSchema(let found, let supported):
            return "Unsupported index schema \(found). This engine supports schema \(supported)."
        case .dimensionMismatch(let manifest, let index):
            return "Index dimension mismatch. Manifest=\(manifest), records=\(index)."
        case .chunkCountMismatch(let manifest, let index):
            return "Index chunk count mismatch. Manifest=\(manifest), records=\(index)."
        }
    }
}
