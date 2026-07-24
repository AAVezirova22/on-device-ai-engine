import Foundation

public struct LocalDocument: Codable, Equatable {
    public let sourcePath: String
    public let title: String
    public let body: String

    public init(sourcePath: String, title: String, body: String) {
        self.sourcePath = sourcePath
        self.title = title
        self.body = body
    }
}

public struct DocumentChunk: Codable, Equatable, Identifiable {
    public let id: String
    public let sourcePath: String
    public let title: String
    public let text: String
    public let chunkIndex: Int

    public init(sourcePath: String, title: String, text: String, chunkIndex: Int) {
        self.sourcePath = sourcePath
        self.title = title
        self.text = text
        self.chunkIndex = chunkIndex
        self.id = "\(sourcePath)#chunk-\(chunkIndex)"
    }
}

public struct RetrievedChunk: Codable, Equatable {
    public let chunk: DocumentChunk
    public let score: Float

    public init(chunk: DocumentChunk, score: Float) {
        self.chunk = chunk
        self.score = score
    }
}
