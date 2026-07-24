import Foundation

public struct RecursiveChunker {
    public let targetWords: Int
    public let overlapWords: Int

    public init(targetWords: Int = 180, overlapWords: Int = 36) {
        precondition(targetWords > 20, "targetWords should be large enough to preserve context.")
        precondition(overlapWords >= 0 && overlapWords < targetWords, "overlapWords must be smaller than targetWords.")
        self.targetWords = targetWords
        self.overlapWords = overlapWords
    }

    public func chunk(_ document: LocalDocument) -> [DocumentChunk] {
        let paragraphs = document.body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sourceUnits = paragraphs.isEmpty ? [document.body] : paragraphs
        var chunks: [DocumentChunk] = []
        var currentWords: [String] = []

        func flush() {
            guard !currentWords.isEmpty else { return }
            let text = currentWords.joined(separator: " ")
            chunks.append(
                DocumentChunk(
                    sourcePath: document.sourcePath,
                    title: document.title,
                    text: text,
                    chunkIndex: chunks.count
                )
            )

            if overlapWords == 0 {
                currentWords.removeAll(keepingCapacity: true)
            } else {
                currentWords = Array(currentWords.suffix(overlapWords))
            }
        }

        for unit in sourceUnits {
            let words = unit.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            if words.count > targetWords {
                for word in words {
                    currentWords.append(word)
                    if currentWords.count >= targetWords {
                        flush()
                    }
                }
            } else {
                if currentWords.count + words.count > targetWords {
                    flush()
                }
                currentWords.append(contentsOf: words)
            }
        }

        if currentWords.count > overlapWords || chunks.isEmpty {
            flush()
        }

        return chunks
    }
}
