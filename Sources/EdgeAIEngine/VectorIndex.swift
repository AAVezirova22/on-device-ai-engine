import Foundation

public struct IndexedChunk: Codable, Equatable {
    public let chunk: DocumentChunk
    public let embedding: [Float]

    public init(chunk: DocumentChunk, embedding: [Float]) {
        self.chunk = chunk
        self.embedding = embedding
    }
}

public struct VectorIndex: Codable, Equatable {
    public let embeddingDimensions: Int
    public private(set) var records: [IndexedChunk]

    public init(embeddingDimensions: Int, records: [IndexedChunk] = []) {
        self.embeddingDimensions = embeddingDimensions
        self.records = records
    }

    public var count: Int {
        records.count
    }

    public mutating func add(_ chunks: [DocumentChunk], using embeddingModel: EmbeddingModel) {
        precondition(embeddingModel.dimensions == embeddingDimensions, "Embedding dimensions must match index dimensions.")
        records.append(contentsOf: chunks.map { chunk in
            IndexedChunk(chunk: chunk, embedding: embeddingModel.embed(chunk.text))
        })
    }

    public func search(
        query: String,
        using embeddingModel: EmbeddingModel,
        topK: Int = 5,
        minimumScore: Float = 0
    ) -> [RetrievedChunk] {
        precondition(embeddingModel.dimensions == embeddingDimensions, "Embedding dimensions must match index dimensions.")
        let queryEmbedding = embeddingModel.embed(query)

        return records
            .map { record in
                RetrievedChunk(
                    chunk: record.chunk,
                    score: VectorMath.dot(queryEmbedding, record.embedding)
                )
            }
            .filter { $0.score >= minimumScore }
            .sorted { $0.score > $1.score }
            .prefix(max(0, topK))
            .map { $0 }
    }
}
