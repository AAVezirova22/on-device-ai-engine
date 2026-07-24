import XCTest
@testable import EdgeAIEngine

final class EdgeAIEngineTests: XCTestCase {
    func testHashEmbeddingIsNormalized() {
        let model = HashEmbeddingModel(dimensions: 64)
        let vector = model.embed("local private ai local documents")
        let magnitude = sqrt(vector.reduce(Float(0)) { $0 + ($1 * $1) })
        XCTAssertEqual(magnitude, 1, accuracy: 0.0001)
    }

    func testChunkerSplitsWithOverlap() {
        let words = (0..<80).map { "word\($0)" }.joined(separator: " ")
        let document = LocalDocument(sourcePath: "/tmp/doc.md", title: "doc", body: words)
        let chunks = RecursiveChunker(targetWords: 30, overlapWords: 5).chunk(document)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks[1].text.contains("word25"))
    }

    func testVectorSearchFindsRelevantChunk() {
        let model = HashEmbeddingModel(dimensions: 128)
        let chunks = [
            DocumentChunk(sourcePath: "/docs/a.md", title: "Thermals", text: "Thermal throttling reduces context size during serious heat.", chunkIndex: 0),
            DocumentChunk(sourcePath: "/docs/b.md", title: "Cooking", text: "Pasta needs salted boiling water.", chunkIndex: 0)
        ]

        var index = VectorIndex(embeddingDimensions: model.dimensions)
        index.add(chunks, using: model)

        let results = index.search(query: "How does thermal throttling work?", using: model, topK: 1)
        XCTAssertEqual(results.first?.chunk.title, "Thermals")
    }

    func testEmbeddingFactoryCreatesHashModelWithRequestedDimensions() throws {
        let model = try EmbeddingModelFactory.make(identifier: "hash", dimensions: 96)

        XCTAssertEqual(model.identifier, "hash")
        XCTAssertEqual(model.dimensions, 96)
    }

    func testNaturalLanguageEmbeddingFactoryIfAvailable() throws {
        do {
            let model = try EmbeddingModelFactory.make(identifier: "natural")
            XCTAssertEqual(model.identifier, "natural")
            XCTAssertGreaterThan(model.dimensions, 0)
            XCTAssertEqual(model.embed("local semantic retrieval").count, model.dimensions)
        } catch EmbeddingModelError.unavailable {
            throw XCTSkip("NaturalLanguage embeddings are unavailable on this system.")
        }
    }

    func testRAGEngineReturnsCitations() async throws {
        let model = HashEmbeddingModel(dimensions: 128)
        var index = VectorIndex(embeddingDimensions: model.dimensions)
        index.add([
            DocumentChunk(sourcePath: "/docs/rag.md", title: "RAG", text: "Retrieval augmented generation finds local chunks before asking the model.", chunkIndex: 0)
        ], using: model)

        let engine = RAGEngine(index: index, embeddingModel: model, llm: ExtractiveLocalLLM())
        let answer = try await engine.answer(question: "What does retrieval augmented generation do?")

        XCTAssertFalse(answer.answer.isEmpty)
        XCTAssertEqual(answer.citations.first?.chunk.title, "RAG")
    }

    func testIndexBuilderCreatesValidatedManifest() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("notes.md")
        try "# Notes\n\nLocal AI should cite local sources.".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try IndexBuilder.build(
            inputURLs: [tempDirectory],
            embeddingModel: HashEmbeddingModel(dimensions: 64),
            chunking: ChunkingConfiguration(targetWords: 40, overlapWords: 5)
        )

        XCTAssertEqual(result.storedIndex.manifest.schemaVersion, EngineVersion.indexSchemaVersion)
        XCTAssertEqual(result.storedIndex.manifest.documentCount, 1)
        XCTAssertEqual(result.storedIndex.manifest.chunkCount, result.storedIndex.index.count)
        XCTAssertEqual(result.storedIndex.manifest.embeddingDimensions, 64)
        XCTAssertEqual(result.storedIndex.manifest.embeddingModel, "hash")
        XCTAssertEqual(result.storedIndex.manifest.sourceDocuments.first?.title, "notes")
        XCTAssertFalse(result.storedIndex.manifest.sourceDocuments.first?.contentFingerprint.isEmpty ?? true)
        XCTAssertNoThrow(try IndexStore.validate(result.storedIndex))
    }

    func testIndexStoreRejectsCorruptManifest() {
        let index = VectorIndex(embeddingDimensions: 64)
        let manifest = IndexManifest(
            embeddingModel: "test",
            embeddingDimensions: 32,
            documentCount: 0,
            chunkCount: 0,
            totalContentBytes: 0,
            chunking: ChunkingConfiguration()
        )
        let stored = StoredIndex(manifest: manifest, index: index)

        XCTAssertThrowsError(try IndexStore.validate(stored))
    }

    func testResourceGuardClampsTopKToBudget() {
        let guardrail = ResourceGuard(
            budget: ResourceBudget(maxInputBytes: 1024, maxChunksPerPrompt: 3)
        )

        XCTAssertEqual(guardrail.admittedTopK(requested: 20), 3)
    }

    func testConfigurationRoundTripsThroughJSON() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempDirectory.appendingPathComponent("config.json")
        let configuration = EdgeAIConfiguration(
            indexPath: ".edgeai/custom.json",
            inputPaths: ["sample_docs"],
            chunking: ChunkingConfiguration(targetWords: 120, overlapWords: 24),
            retrieval: RetrievalConfiguration(topK: 4, minimumScore: 0.05),
            generation: GenerationConfiguration(llamaServerURL: "http://127.0.0.1:8080", maxTokens: 256, temperature: 0.1),
            resources: ResourceConfiguration(maxInputMB: 100, maxResidentMB: 2048, maxChunksPerPrompt: 4),
            hotkey: HotkeyConfiguration(key: "k", modifiers: ["control", "command"])
        )

        try EdgeAIConfigurationStore.save(configuration, to: configURL)
        let loaded = try EdgeAIConfigurationStore.load(from: configURL)

        XCTAssertEqual(loaded, configuration)
        XCTAssertEqual(loaded.resources.budget.maxInputBytes, 100 * 1024 * 1024)
        XCTAssertEqual(loaded.resources.budget.maxResidentMemoryBytes, 2048 * 1024 * 1024)
    }

    func testConfigurationDefaultsMissingFieldsForCompatibility() throws {
        let data = """
        {
          "indexPath": ".edgeai/legacy.json",
          "inputPaths": ["sample_docs"]
        }
        """.data(using: .utf8)!

        let configuration = try JSONDecoder().decode(EdgeAIConfiguration.self, from: data)

        XCTAssertEqual(configuration.indexPath, ".edgeai/legacy.json")
        XCTAssertEqual(configuration.inputPaths, ["sample_docs"])
        XCTAssertEqual(configuration.embeddingModel, "hash")
        XCTAssertEqual(configuration.hotkey, HotkeyConfiguration())
        XCTAssertEqual(configuration.chunking, ChunkingConfiguration())
        XCTAssertEqual(configuration.retrieval, RetrievalConfiguration())
    }
}
