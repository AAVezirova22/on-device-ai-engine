import Foundation

public struct IndexedChunk: Codable, Equatable {
    public let chunk: DocumentChunk
    public let embedding: [Float]

    public init(chunk: DocumentChunk, embedding: [Float]) {
        self.chunk = chunk
        self.embedding = embedding
    }
}

public enum VectorSearchMode: String, Codable, CaseIterable {
    case exact
    case approximate
    case auto
}

public enum VectorScoringBackend: String, Codable, CaseIterable {
    case auto
    case swift
    case nativeCxx = "native-cxx"
    case metal
}

public struct ApproximateNearestNeighborIndex: Codable, Equatable {
    public let tableCount: Int
    public let hyperplanesPerTable: Int
    public let buckets: [String: [Int]]

    public init(
        records: [IndexedChunk],
        tableCount: Int = 8,
        hyperplanesPerTable: Int = 12
    ) {
        self.tableCount = tableCount
        self.hyperplanesPerTable = hyperplanesPerTable

        var mutableBuckets: [String: [Int]] = [:]
        for (recordIndex, record) in records.enumerated() {
            for table in 0..<tableCount {
                let key = Self.bucketKey(
                    table: table,
                    signature: Self.signature(
                        for: record.embedding,
                        table: table,
                        hyperplanesPerTable: hyperplanesPerTable
                    )
                )
                mutableBuckets[key, default: []].append(recordIndex)
            }
        }

        self.buckets = mutableBuckets
    }

    public func candidateIndices(for embedding: [Float]) -> Set<Int> {
        var candidates = Set<Int>()
        for table in 0..<tableCount {
            let key = Self.bucketKey(
                table: table,
                signature: Self.signature(
                    for: embedding,
                    table: table,
                    hyperplanesPerTable: hyperplanesPerTable
                )
            )
            candidates.formUnion(buckets[key] ?? [])
        }
        return candidates
    }

    private static func bucketKey(table: Int, signature: UInt64) -> String {
        "\(table):\(signature)"
    }

    private static func signature(
        for vector: [Float],
        table: Int,
        hyperplanesPerTable: Int
    ) -> UInt64 {
        var signature: UInt64 = 0

        for plane in 0..<hyperplanesPerTable {
            var projection: Float = 0
            for dimension in vector.indices {
                projection += vector[dimension] * projectionWeight(
                    table: table,
                    plane: plane,
                    dimension: dimension
                )
            }
            if projection >= 0 {
                signature |= (1 << UInt64(plane))
            }
        }

        return signature
    }

    private static func projectionWeight(table: Int, plane: Int, dimension: Int) -> Float {
        let hash = StableHash.fnv1a64("edgeai:lsh:\(table):\(plane):\(dimension)")
        let magnitude = Float((hash % 1_000) + 1) / 1_000
        return (hash & 1) == 0 ? magnitude : -magnitude
    }
}

public struct VectorIndex: Codable, Equatable {
    public let embeddingDimensions: Int
    public private(set) var records: [IndexedChunk]
    public private(set) var approximateIndex: ApproximateNearestNeighborIndex?

    public init(
        embeddingDimensions: Int,
        records: [IndexedChunk] = [],
        approximateIndex: ApproximateNearestNeighborIndex? = nil
    ) {
        self.embeddingDimensions = embeddingDimensions
        self.records = records
        self.approximateIndex = approximateIndex
    }

    public var count: Int {
        records.count
    }

    public mutating func add(_ chunks: [DocumentChunk], using embeddingModel: EmbeddingModel) {
        precondition(embeddingModel.dimensions == embeddingDimensions, "Embedding dimensions must match index dimensions.")
        records.append(contentsOf: chunks.map { chunk in
            IndexedChunk(chunk: chunk, embedding: embeddingModel.embed(chunk.text))
        })
        rebuildApproximateIndex()
    }

    public mutating func rebuildApproximateIndex(
        tableCount: Int = 8,
        hyperplanesPerTable: Int = 12
    ) {
        approximateIndex = ApproximateNearestNeighborIndex(
            records: records,
            tableCount: tableCount,
            hyperplanesPerTable: hyperplanesPerTable
        )
    }

    public func search(
        query: String,
        using embeddingModel: EmbeddingModel,
        topK: Int = 5,
        minimumScore: Float = 0,
        mode: VectorSearchMode = .exact,
        scoringBackend: VectorScoringBackend = .auto
    ) -> [RetrievedChunk] {
        precondition(embeddingModel.dimensions == embeddingDimensions, "Embedding dimensions must match index dimensions.")
        let queryEmbedding = embeddingModel.embed(query)
        let recordPool = recordsForSearch(queryEmbedding: queryEmbedding, mode: mode)

        return recordPool
            .map { _, record in
                RetrievedChunk(
                    chunk: record.chunk,
                    score: VectorMath.dot(queryEmbedding, record.embedding, backend: scoringBackend)
                )
            }
            .filter { $0.score >= minimumScore }
            .sorted { $0.score > $1.score }
            .prefix(max(0, topK))
            .map { $0 }
    }

    private func recordsForSearch(
        queryEmbedding: [Float],
        mode: VectorSearchMode
    ) -> [(Int, IndexedChunk)] {
        let selectedMode: VectorSearchMode
        if mode == .auto {
            selectedMode = records.count >= 256 ? .approximate : .exact
        } else {
            selectedMode = mode
        }

        guard selectedMode == .approximate,
              let approximateIndex else {
            return Array(records.enumerated())
        }

        let candidates = approximateIndex.candidateIndices(for: queryEmbedding)
        guard !candidates.isEmpty else {
            return Array(records.enumerated())
        }

        return candidates
            .sorted()
            .compactMap { index in
                guard records.indices.contains(index) else { return nil }
                return (index, records[index])
            }
    }
}
