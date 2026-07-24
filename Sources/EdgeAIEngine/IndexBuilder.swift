import Foundation

public struct ChunkingConfiguration: Codable, Equatable {
    public let targetWords: Int
    public let overlapWords: Int

    public init(targetWords: Int = 180, overlapWords: Int = 36) {
        self.targetWords = targetWords
        self.overlapWords = overlapWords
    }
}

public struct IndexBuildMetrics: Codable, Equatable {
    public let durationMilliseconds: Double
    public let documentsPerSecond: Double
    public let chunksPerSecond: Double

    public init(durationMilliseconds: Double, documentCount: Int, chunkCount: Int) {
        self.durationMilliseconds = durationMilliseconds
        let seconds = max(durationMilliseconds / 1_000, 0.000_001)
        self.documentsPerSecond = Double(documentCount) / seconds
        self.chunksPerSecond = Double(chunkCount) / seconds
    }
}

public struct IndexBuildResult: Equatable {
    public let storedIndex: StoredIndex
    public let metrics: IndexBuildMetrics

    public init(storedIndex: StoredIndex, metrics: IndexBuildMetrics) {
        self.storedIndex = storedIndex
        self.metrics = metrics
    }
}

public enum IndexBuilder {
    public static func build(
        inputURLs: [URL],
        embeddingModel: EmbeddingModel = HashEmbeddingModel(),
        chunking: ChunkingConfiguration = ChunkingConfiguration(),
        resourceGuard: ResourceGuard = ResourceGuard()
    ) throws -> IndexBuildResult {
        let start = DispatchTime.now()
        try resourceGuard.validateSystemForWorkload()
        let documents = try DocumentLoader.loadDocuments(from: inputURLs)
        let totalBytes = documents.reduce(0) { $0 + $1.body.utf8.count }
        try resourceGuard.validateInputSize(totalBytes)
        try resourceGuard.validateSystemForWorkload()

        let chunker = RecursiveChunker(
            targetWords: chunking.targetWords,
            overlapWords: chunking.overlapWords
        )
        let chunks = documents.flatMap(chunker.chunk)

        var vectorIndex = VectorIndex(embeddingDimensions: embeddingModel.dimensions)
        vectorIndex.add(chunks, using: embeddingModel)

        let elapsed = millisecondsSince(start)
        let metrics = IndexBuildMetrics(
            durationMilliseconds: elapsed,
            documentCount: documents.count,
            chunkCount: chunks.count
        )

        let manifest = IndexManifest(
            embeddingModel: embeddingModel.identifier,
            embeddingDimensions: embeddingModel.dimensions,
            documentCount: documents.count,
            chunkCount: chunks.count,
            totalContentBytes: totalBytes,
            chunking: chunking,
            buildMetrics: metrics,
            sourceDocuments: documents.map(SourceDocumentMetadata.init)
        )

        return IndexBuildResult(
            storedIndex: StoredIndex(manifest: manifest, index: vectorIndex),
            metrics: metrics
        )
    }

    private static func millisecondsSince(_ start: DispatchTime) -> Double {
        let end = DispatchTime.now()
        let nanos = end.uptimeNanoseconds - start.uptimeNanoseconds
        return Double(nanos) / 1_000_000
    }
}
