import Foundation

public struct EdgeAIConfiguration: Codable, Equatable {
    public var indexPath: String
    public var inputPaths: [String]
    public var embeddingModel: String
    public var chunking: ChunkingConfiguration
    public var retrieval: RetrievalConfiguration
    public var generation: GenerationConfiguration
    public var resources: ResourceConfiguration
    public var hotkey: HotkeyConfiguration

    public init(
        indexPath: String = ".edgeai/index.json",
        inputPaths: [String] = [],
        embeddingModel: String = "hash",
        chunking: ChunkingConfiguration = ChunkingConfiguration(),
        retrieval: RetrievalConfiguration = RetrievalConfiguration(),
        generation: GenerationConfiguration = GenerationConfiguration(),
        resources: ResourceConfiguration = ResourceConfiguration(),
        hotkey: HotkeyConfiguration = HotkeyConfiguration()
    ) {
        self.indexPath = indexPath
        self.inputPaths = inputPaths
        self.embeddingModel = embeddingModel
        self.chunking = chunking
        self.retrieval = retrieval
        self.generation = generation
        self.resources = resources
        self.hotkey = hotkey
    }

    public static let `default` = EdgeAIConfiguration()

    enum CodingKeys: String, CodingKey {
        case indexPath
        case inputPaths
        case embeddingModel
        case chunking
        case retrieval
        case generation
        case resources
        case hotkey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.indexPath = try container.decodeIfPresent(String.self, forKey: .indexPath) ?? Self.default.indexPath
        self.inputPaths = try container.decodeIfPresent([String].self, forKey: .inputPaths) ?? Self.default.inputPaths
        self.embeddingModel = try container.decodeIfPresent(String.self, forKey: .embeddingModel) ?? Self.default.embeddingModel
        self.chunking = try container.decodeIfPresent(ChunkingConfiguration.self, forKey: .chunking) ?? Self.default.chunking
        self.retrieval = try container.decodeIfPresent(RetrievalConfiguration.self, forKey: .retrieval) ?? Self.default.retrieval
        self.generation = try container.decodeIfPresent(GenerationConfiguration.self, forKey: .generation) ?? Self.default.generation
        self.resources = try container.decodeIfPresent(ResourceConfiguration.self, forKey: .resources) ?? Self.default.resources
        self.hotkey = try container.decodeIfPresent(HotkeyConfiguration.self, forKey: .hotkey) ?? Self.default.hotkey
    }
}

public struct RetrievalConfiguration: Codable, Equatable {
    public var topK: Int
    public var minimumScore: Float
    public var searchMode: VectorSearchMode
    public var scoringBackend: VectorScoringBackend

    public init(
        topK: Int = 5,
        minimumScore: Float = 0.01,
        searchMode: VectorSearchMode = .exact,
        scoringBackend: VectorScoringBackend = .auto
    ) {
        self.topK = topK
        self.minimumScore = minimumScore
        self.searchMode = searchMode
        self.scoringBackend = scoringBackend
    }

    enum CodingKeys: String, CodingKey {
        case topK
        case minimumScore
        case searchMode
        case scoringBackend
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.topK = try container.decodeIfPresent(Int.self, forKey: .topK) ?? Self().topK
        self.minimumScore = try container.decodeIfPresent(Float.self, forKey: .minimumScore) ?? Self().minimumScore
        self.searchMode = try container.decodeIfPresent(VectorSearchMode.self, forKey: .searchMode) ?? Self().searchMode
        self.scoringBackend = try container.decodeIfPresent(VectorScoringBackend.self, forKey: .scoringBackend) ?? Self().scoringBackend
    }
}

public struct GenerationConfiguration: Codable, Equatable {
    public var runtime: LocalRuntimeKind
    public var llamaServerURL: String?
    public var modelPath: String?
    public var host: String
    public var port: Int
    public var contextSize: Int
    public var maxTokens: Int
    public var temperature: Double

    public init(
        runtime: LocalRuntimeKind = .extractive,
        llamaServerURL: String? = nil,
        modelPath: String? = nil,
        host: String = "127.0.0.1",
        port: Int = 8080,
        contextSize: Int = 4096,
        maxTokens: Int = 512,
        temperature: Double = 0.2
    ) {
        self.runtime = runtime
        self.llamaServerURL = llamaServerURL
        self.modelPath = modelPath
        self.host = host
        self.port = port
        self.contextSize = contextSize
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    enum CodingKeys: String, CodingKey {
        case runtime
        case llamaServerURL
        case modelPath
        case host
        case port
        case contextSize
        case maxTokens
        case temperature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.runtime = try container.decodeIfPresent(LocalRuntimeKind.self, forKey: .runtime) ?? Self().runtime
        self.llamaServerURL = try container.decodeIfPresent(String.self, forKey: .llamaServerURL)
        self.modelPath = try container.decodeIfPresent(String.self, forKey: .modelPath)
        self.host = try container.decodeIfPresent(String.self, forKey: .host) ?? Self().host
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? Self().port
        self.contextSize = try container.decodeIfPresent(Int.self, forKey: .contextSize) ?? Self().contextSize
        self.maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? Self().maxTokens
        self.temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? Self().temperature
    }

    public var effectiveServerURL: String {
        llamaServerURL ?? "http://\(host):\(port)"
    }

    public func llamaServerCommand(executable: String = "llama-server") -> [String] {
        var command = [
            executable
        ]

        if let modelPath, !modelPath.isEmpty {
            command.append(contentsOf: ["-m", modelPath])
        }

        command.append(contentsOf: [
            "-c", String(contextSize),
            "--host", host,
            "--port", String(port)
        ])

        return command
    }
}

public struct ResourceConfiguration: Codable, Equatable {
    public var maxInputMB: Int
    public var maxResidentMB: UInt64?
    public var maxChunksPerPrompt: Int
    public var reduceContextWhenThermalsElevated: Bool

    public init(
        maxInputMB: Int = 50,
        maxResidentMB: UInt64? = nil,
        maxChunksPerPrompt: Int = 6,
        reduceContextWhenThermalsElevated: Bool = true
    ) {
        self.maxInputMB = maxInputMB
        self.maxResidentMB = maxResidentMB
        self.maxChunksPerPrompt = maxChunksPerPrompt
        self.reduceContextWhenThermalsElevated = reduceContextWhenThermalsElevated
    }

    public var budget: ResourceBudget {
        ResourceBudget(
            maxInputBytes: maxInputMB * 1024 * 1024,
            maxChunksPerPrompt: maxChunksPerPrompt,
            reduceContextWhenThermalsElevated: reduceContextWhenThermalsElevated,
            maxResidentMemoryBytes: maxResidentMB.map { $0 * 1024 * 1024 }
        )
    }
}

public struct HotkeyConfiguration: Codable, Equatable {
    public var key: String
    public var modifiers: [String]

    public init(
        key: String = "s",
        modifiers: [String] = ["control", "option", "command"]
    ) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum EdgeAIConfigurationStore {
    public static let defaultPath = ".edgeai/config.json"

    public static func load(from url: URL) throws -> EdgeAIConfiguration {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(EdgeAIConfiguration.self, from: data)
    }

    public static func save(_ configuration: EdgeAIConfiguration, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: url, options: [.atomic])
    }

    public static func loadIfPresent(from url: URL) throws -> EdgeAIConfiguration? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try load(from: url)
    }
}
