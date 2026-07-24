import Foundation

public struct RAGAnswer: Equatable {
    public let answer: String
    public let citations: [RetrievedChunk]
    public let retrievalMilliseconds: Double

    public init(answer: String, citations: [RetrievedChunk], retrievalMilliseconds: Double = 0) {
        self.answer = answer
        self.citations = citations
        self.retrievalMilliseconds = retrievalMilliseconds
    }
}

public struct RAGOptions: Equatable {
    public let topK: Int
    public let minimumScore: Float
    public let llmOptions: LLMOptions

    public init(topK: Int = 5, minimumScore: Float = 0.01, llmOptions: LLMOptions = LLMOptions()) {
        self.topK = topK
        self.minimumScore = minimumScore
        self.llmOptions = llmOptions
    }
}

public final class RAGEngine {
    private let index: VectorIndex
    private let embeddingModel: EmbeddingModel
    private let llm: LocalLLM
    private let resourceGuard: ResourceGuard

    public init(
        index: VectorIndex,
        embeddingModel: EmbeddingModel,
        llm: LocalLLM,
        resourceGuard: ResourceGuard = ResourceGuard()
    ) {
        self.index = index
        self.embeddingModel = embeddingModel
        self.llm = llm
        self.resourceGuard = resourceGuard
    }

    public func answer(question: String, topK: Int = 5) async throws -> RAGAnswer {
        try await answer(question: question, options: RAGOptions(topK: topK))
    }

    public func answer(question: String, options: RAGOptions) async throws -> RAGAnswer {
        try resourceGuard.validateSystemForWorkload()
        let retrievalStart = DispatchTime.now()
        let admittedTopK = resourceGuard.admittedTopK(requested: options.topK)
        guard admittedTopK > 0 else {
            throw ResourceGuardError.thermalsCritical
        }

        let matches = index.search(
            query: question,
            using: embeddingModel,
            topK: admittedTopK,
            minimumScore: options.minimumScore
        )
        let retrievalMilliseconds = elapsedMilliseconds(since: retrievalStart)

        let prompt = PromptBuilder.ragPrompt(question: question, matches: matches)
        let answer = try await llm.complete(prompt: prompt, options: options.llmOptions)
        return RAGAnswer(answer: answer, citations: matches, retrievalMilliseconds: retrievalMilliseconds)
    }

    public func retrieve(question: String, topK: Int = 5, minimumScore: Float = 0.01) throws -> [RetrievedChunk] {
        try resourceGuard.validateSystemForWorkload()
        let admittedTopK = resourceGuard.admittedTopK(requested: topK)
        guard admittedTopK > 0 else {
            throw ResourceGuardError.thermalsCritical
        }

        return index.search(
            query: question,
            using: embeddingModel,
            topK: admittedTopK,
            minimumScore: minimumScore
        )
    }
}

public enum PromptBuilder {
    public static func ragPrompt(question: String, matches: [RetrievedChunk]) -> String {
        let context = matches.enumerated().map { index, match in
            """
            [\(index + 1)] \(match.chunk.title) — \(match.chunk.sourcePath)
            \(match.chunk.text)
            """
        }.joined(separator: "\n\n")

        return """
        You are an offline, privacy-first assistant. Answer using only the local context.
        If the context is insufficient, say that clearly.

        Context:
        \(context)

        Question:
        \(question)

        Answer with concise bullets and cite sources by bracket number.
        """
    }
}

private func elapsedMilliseconds(since start: DispatchTime) -> Double {
    let end = DispatchTime.now()
    return Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
}
