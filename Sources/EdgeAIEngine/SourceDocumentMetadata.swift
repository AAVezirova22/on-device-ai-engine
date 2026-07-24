import Foundation

public struct SourceDocumentMetadata: Codable, Equatable {
    public let sourcePath: String
    public let title: String
    public let byteCount: Int
    public let contentFingerprint: String

    public init(sourcePath: String, title: String, byteCount: Int, contentFingerprint: String) {
        self.sourcePath = sourcePath
        self.title = title
        self.byteCount = byteCount
        self.contentFingerprint = contentFingerprint
    }

    public init(document: LocalDocument) {
        self.init(
            sourcePath: document.sourcePath,
            title: document.title,
            byteCount: document.body.utf8.count,
            contentFingerprint: StableHash.hexFNV1A64(document.body)
        )
    }
}
