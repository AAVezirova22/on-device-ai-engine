import EdgeAIEngine
import Foundation

@main
struct EdgeAICommand {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let command = arguments.first else {
                printHelp()
                return
            }

            switch command {
            case "index":
                try await index(arguments: Array(arguments.dropFirst()))
            case "ask":
                try await ask(arguments: Array(arguments.dropFirst()))
            case "search":
                try search(arguments: Array(arguments.dropFirst()))
            case "inspect":
                try inspect(arguments: Array(arguments.dropFirst()))
            case "benchmark":
                try benchmark(arguments: Array(arguments.dropFirst()))
            case "resources":
                try resources(arguments: Array(arguments.dropFirst()))
            case "doctor":
                try await doctor(arguments: Array(arguments.dropFirst()))
            case "model-info":
                try modelInfo(arguments: Array(arguments.dropFirst()))
            case "llama-command":
                try llamaCommand(arguments: Array(arguments.dropFirst()))
            case "init-config":
                try initConfig(arguments: Array(arguments.dropFirst()))
            case "show-config":
                try showConfig(arguments: Array(arguments.dropFirst()))
            case "version", "--version":
                print(EngineVersion.current)
            case "help", "--help", "-h":
                printHelp()
            default:
                throw CLIError.message("Unknown command: \(command)")
            }
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func index(arguments: [String]) async throws {
        let parser = ArgumentParser(arguments)
        let configuration = try loadConfiguration(parser: parser)
        let configuredInputPaths = parser.values(for: "--input")
        let inputPaths = configuredInputPaths.isEmpty ? configuration.inputPaths : configuredInputPaths
        let outputPath = parser.value(for: "--output") ?? configuration.indexPath
        let targetWords = parser.intValue(for: "--target-words") ?? configuration.chunking.targetWords
        let overlapWords = parser.intValue(for: "--overlap-words") ?? configuration.chunking.overlapWords
        let maxInputMB = parser.intValue(for: "--max-input-mb") ?? configuration.resources.maxInputMB
        let embeddingName = parser.value(for: "--embedding") ?? configuration.embeddingModel
        let json = parser.hasFlag("--json")

        guard !inputPaths.isEmpty else {
            throw CLIError.message("index requires at least one --input path.")
        }

        let inputURLs = inputPaths.map { URL(fileURLWithPath: $0) }
        let embeddingModel = try EmbeddingModelFactory.make(identifier: embeddingName)
        let result = try IndexBuilder.build(
            inputURLs: inputURLs,
            embeddingModel: embeddingModel,
            chunking: ChunkingConfiguration(targetWords: targetWords, overlapWords: overlapWords),
            resourceGuard: resourceGuard(parser: parser, configuration: configuration, maxInputMB: maxInputMB)
        )

        try IndexStore.save(result.storedIndex, to: URL(fileURLWithPath: outputPath))

        if json {
            try printJSON(IndexCommandResponse(indexPath: outputPath, manifest: result.storedIndex.manifest))
        } else {
            print("Indexed \(result.storedIndex.manifest.documentCount) documents into \(result.storedIndex.manifest.chunkCount) chunks.")
            print("Saved: \(outputPath)")
            print("Build time: \(format(milliseconds: result.metrics.durationMilliseconds))")
            print("Throughput: \(String(format: "%.1f", result.metrics.chunksPerSecond)) chunks/sec")
        }
    }

    private static func ask(arguments: [String]) async throws {
        let parser = ArgumentParser(arguments)
        let configuration = try loadConfiguration(parser: parser)
        let indexPath = parser.value(for: "--index") ?? configuration.indexPath
        let question = parser.value(for: "--question") ?? parser.positionalArguments.joined(separator: " ")
        let topK = parser.intValue(for: "--top-k") ?? configuration.retrieval.topK
        let minimumScore = parser.floatValue(for: "--min-score") ?? configuration.retrieval.minimumScore
        let maxTokens = parser.intValue(for: "--max-tokens") ?? configuration.generation.maxTokens
        let temperature = parser.doubleValue(for: "--temperature") ?? configuration.generation.temperature
        let json = parser.hasFlag("--json")

        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError.message("ask requires --question or a positional question.")
        }

        let stored = try IndexStore.load(from: URL(fileURLWithPath: indexPath))
        let embeddingModel = try EmbeddingModelFactory.make(
            identifier: stored.manifest.embeddingModel,
            dimensions: stored.index.embeddingDimensions
        )
        let llm: LocalLLM

        if let llamaServer = parser.value(for: "--llama-server") ?? configuration.generation.llamaServerURL {
            guard let url = URL(string: llamaServer), url.scheme != nil else {
                throw CLIError.message("--llama-server must be a valid URL, for example http://127.0.0.1:8080")
            }
            llm = LlamaCppServerClient(baseURL: url)
        } else {
            llm = ExtractiveLocalLLM()
        }

        let engine = RAGEngine(
            index: stored.index,
            embeddingModel: embeddingModel,
            llm: llm,
            resourceGuard: resourceGuard(parser: parser, configuration: configuration)
        )
        let result = try await engine.answer(
            question: question,
            options: RAGOptions(
                topK: topK,
                minimumScore: minimumScore,
                llmOptions: LLMOptions(maxTokens: maxTokens, temperature: temperature)
            )
        )

        if json {
            try printJSON(AskCommandResponse(question: question, result: result))
        } else {
            print(result.answer)
            print("\nRetrieval: \(format(milliseconds: result.retrievalMilliseconds))")
            if !result.citations.isEmpty {
                print("\nSources:")
                printCitations(result.citations)
            }
        }
    }

    private static func search(arguments: [String]) throws {
        let parser = ArgumentParser(arguments)
        let configuration = try loadConfiguration(parser: parser)
        let indexPath = parser.value(for: "--index") ?? configuration.indexPath
        let query = parser.value(for: "--query") ?? parser.positionalArguments.joined(separator: " ")
        let topK = parser.intValue(for: "--top-k") ?? configuration.retrieval.topK
        let minimumScore = parser.floatValue(for: "--min-score") ?? configuration.retrieval.minimumScore
        let json = parser.hasFlag("--json")

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError.message("search requires --query or a positional query.")
        }

        let stored = try IndexStore.load(from: URL(fileURLWithPath: indexPath))
        let embeddingModel = try EmbeddingModelFactory.make(
            identifier: stored.manifest.embeddingModel,
            dimensions: stored.index.embeddingDimensions
        )
        let engine = RAGEngine(
            index: stored.index,
            embeddingModel: embeddingModel,
            llm: ExtractiveLocalLLM(),
            resourceGuard: resourceGuard(parser: parser, configuration: configuration)
        )
        let results = try engine.retrieve(question: query, topK: topK, minimumScore: minimumScore)

        if json {
            try printJSON(SearchCommandResponse(query: query, citations: results.map(CitationResponse.init)))
        } else if results.isEmpty {
            print("No matching chunks found.")
        } else {
            printCitations(results, includePreview: true)
        }
    }

    private static func inspect(arguments: [String]) throws {
        let parser = ArgumentParser(arguments)
        let configuration = try loadConfiguration(parser: parser)
        let indexPath = parser.value(for: "--index") ?? configuration.indexPath
        let json = parser.hasFlag("--json")
        let stored = try IndexStore.load(from: URL(fileURLWithPath: indexPath))

        if json {
            try printJSON(stored.manifest)
            return
        }

        let manifest = stored.manifest
        print("Index: \(indexPath)")
        print("Schema: \(manifest.schemaVersion)")
        print("Engine: \(manifest.engineVersion)")
        print("Created: \(manifest.createdAt)")
        print("Embedding: \(manifest.embeddingModel), dimensions=\(manifest.embeddingDimensions)")
        print("Documents: \(manifest.documentCount)")
        print("Chunks: \(manifest.chunkCount)")
        print("Content bytes: \(manifest.totalContentBytes)")
        print("Chunking: target=\(manifest.chunking.targetWords), overlap=\(manifest.chunking.overlapWords)")
        if let metrics = manifest.buildMetrics {
            print("Build time: \(format(milliseconds: metrics.durationMilliseconds))")
            print("Throughput: \(String(format: "%.1f", metrics.chunksPerSecond)) chunks/sec")
        }

        if !manifest.sourceDocuments.isEmpty {
            print("\nSources:")
            for source in manifest.sourceDocuments {
                print("- \(source.title) — \(source.sourcePath)")
                print("  bytes=\(source.byteCount), fingerprint=\(source.contentFingerprint)")
            }
        }
    }

    private static func benchmark(arguments: [String]) throws {
        let parser = ArgumentParser(arguments)
        let configuration = try loadConfiguration(parser: parser)
        let configuredInputPaths = parser.values(for: "--input")
        let inputPaths = configuredInputPaths.isEmpty ? configuration.inputPaths : configuredInputPaths
        let query = parser.value(for: "--query") ?? "What are the action items?"
        let iterations = max(1, parser.intValue(for: "--iterations") ?? 25)
        let topK = parser.intValue(for: "--top-k") ?? configuration.retrieval.topK
        let json = parser.hasFlag("--json")

        guard !inputPaths.isEmpty else {
            throw CLIError.message("benchmark requires at least one --input path.")
        }

        let before = SystemResourceMonitor.snapshot()
        let guardrail = resourceGuard(parser: parser, configuration: configuration)
        let embeddingName = parser.value(for: "--embedding") ?? configuration.embeddingModel
        let build = try IndexBuilder.build(
            inputURLs: inputPaths.map { URL(fileURLWithPath: $0) },
            embeddingModel: try EmbeddingModelFactory.make(identifier: embeddingName),
            resourceGuard: guardrail
        )
        let embeddingModel = try EmbeddingModelFactory.make(
            identifier: build.storedIndex.manifest.embeddingModel,
            dimensions: build.storedIndex.index.embeddingDimensions
        )
        let engine = RAGEngine(
            index: build.storedIndex.index,
            embeddingModel: embeddingModel,
            llm: ExtractiveLocalLLM(),
            resourceGuard: guardrail
        )

        var retrievalDurations: [Double] = []
        retrievalDurations.reserveCapacity(iterations)

        for _ in 0..<iterations {
            let start = DispatchTime.now()
            _ = try engine.retrieve(question: query, topK: topK)
            retrievalDurations.append(elapsedMilliseconds(since: start))
        }

        let after = SystemResourceMonitor.snapshot()
        let result = BenchmarkCommandResponse(
            query: query,
            iterations: iterations,
            manifest: build.storedIndex.manifest,
            buildMetrics: build.metrics,
            retrieval: LatencySummary(milliseconds: retrievalDurations),
            resourcesBefore: before,
            resourcesAfter: after
        )

        if json {
            try printJSON(result)
        } else {
            print("Documents: \(result.manifest.documentCount)")
            print("Chunks: \(result.manifest.chunkCount)")
            print("Build: \(format(milliseconds: result.buildMetrics.durationMilliseconds))")
            print("Retrieval avg: \(format(milliseconds: result.retrieval.averageMilliseconds))")
            print("Retrieval p95: \(format(milliseconds: result.retrieval.p95Milliseconds))")
            print("Resident memory before: \(format(bytes: before.residentMemoryBytes))")
            print("Resident memory after: \(format(bytes: after.residentMemoryBytes))")
            print("Thermal state: \(after.thermalState)")
        }
    }

    private static func resources(arguments: [String]) throws {
        let parser = ArgumentParser(arguments)
        let snapshot = SystemResourceMonitor.snapshot()

        if parser.hasFlag("--json") {
            try printJSON(snapshot)
        } else {
            print("Thermal state: \(snapshot.thermalState)")
            print("Physical memory: \(format(bytes: snapshot.physicalMemoryBytes))")
            print("Resident memory: \(format(bytes: snapshot.residentMemoryBytes))")
        }
    }

    private static func doctor(arguments: [String]) async throws {
        let parser = ArgumentParser(arguments)
        var checks: [DoctorCheck] = []
        let configPath = parser.value(for: "--config") ?? EdgeAIConfigurationStore.defaultPath
        let configURL = URL(fileURLWithPath: configPath)
        let configuration: EdgeAIConfiguration

        do {
            configuration = try EdgeAIConfigurationStore.loadIfPresent(from: configURL) ?? .default
            let detail = FileManager.default.fileExists(atPath: configURL.path)
                ? "Loaded configuration from \(configPath)."
                : "No config file found at \(configPath); using built-in defaults."
            checks.append(DoctorCheck(name: "configuration", status: .pass, detail: detail))
        } catch {
            let report = DoctorReport(
                checks: [DoctorCheck(name: "configuration", status: .fail, detail: String(describing: error))]
            )
            try emitDoctorReport(report, json: parser.hasFlag("--json"))
            throw CLIError.message("doctor found failures.")
        }

        let snapshot = SystemResourceMonitor.snapshot()
        do {
            try resourceGuard(parser: parser, configuration: configuration).validateSystemForWorkload()
            checks.append(
                DoctorCheck(
                    name: "resources",
                    status: .pass,
                    detail: "thermal=\(snapshot.thermalState), residentMemory=\(format(bytes: snapshot.residentMemoryBytes))"
                )
            )
        } catch {
            checks.append(DoctorCheck(name: "resources", status: .fail, detail: String(describing: error)))
        }

        let embeddingName = parser.value(for: "--embedding") ?? configuration.embeddingModel
        do {
            let model = try EmbeddingModelFactory.make(identifier: embeddingName)
            checks.append(
                DoctorCheck(
                    name: "embedding",
                    status: .pass,
                    detail: "\(model.identifier), dimensions=\(model.dimensions)"
                )
            )
        } catch {
            checks.append(DoctorCheck(name: "embedding", status: .fail, detail: String(describing: error)))
        }

        let indexPath = parser.value(for: "--index") ?? configuration.indexPath
        let requireIndex = parser.hasFlag("--require-index")
        if FileManager.default.fileExists(atPath: indexPath) {
            do {
                let stored = try IndexStore.load(from: URL(fileURLWithPath: indexPath))
                _ = try EmbeddingModelFactory.make(
                    identifier: stored.manifest.embeddingModel,
                    dimensions: stored.index.embeddingDimensions
                )
                checks.append(
                    DoctorCheck(
                        name: "index",
                        status: .pass,
                        detail: "\(indexPath): schema=\(stored.manifest.schemaVersion), chunks=\(stored.index.count), embedding=\(stored.manifest.embeddingModel)"
                    )
                )
            } catch {
                checks.append(DoctorCheck(name: "index", status: .fail, detail: String(describing: error)))
            }
        } else {
            checks.append(
                DoctorCheck(
                    name: "index",
                    status: requireIndex ? .fail : .warn,
                    detail: "Index not found at \(indexPath). Run edgeai index before asking questions."
                )
            )
        }

        if let llamaServer = parser.value(for: "--llama-server") ?? configuration.generation.llamaServerURL {
            if let url = URL(string: llamaServer), url.scheme != nil {
                let health = await LlamaCppServerClient(baseURL: url).healthCheck()
                checks.append(
                    DoctorCheck(
                        name: "llama.cpp",
                        status: health.reachable ? .pass : .fail,
                        detail: "\(health.baseURL): \(health.detail)"
                    )
                )
            } else {
                checks.append(
                    DoctorCheck(
                        name: "llama.cpp",
                        status: .fail,
                        detail: "Invalid llama server URL: \(llamaServer)"
                    )
                )
            }
        } else {
            checks.append(
                DoctorCheck(
                    name: "llama.cpp",
                    status: .pass,
                    detail: "No llama.cpp server configured; deterministic fallback will be used."
                )
            )
        }

        if let modelPath = parser.value(for: "--model") ?? configuration.generation.modelPath {
            if FileManager.default.fileExists(atPath: modelPath) {
                checks.append(DoctorCheck(name: "model", status: .pass, detail: "Model file exists: \(modelPath)"))
            } else {
                checks.append(DoctorCheck(name: "model", status: .fail, detail: "Configured model file not found: \(modelPath)"))
            }
        } else {
            checks.append(DoctorCheck(name: "model", status: .warn, detail: "No model path configured. Use --model or set generation.modelPath."))
        }

        let report = DoctorReport(checks: checks)
        try emitDoctorReport(report, json: parser.hasFlag("--json"))

        if report.hasFailures {
            throw CLIError.message("doctor found failures.")
        }
    }

    private static func emitDoctorReport(_ report: DoctorReport, json: Bool) throws {
        if json {
            try printJSON(report)
            return
        }

        print("Overall: \(report.overallStatus.rawValue)")
        for check in report.checks {
            print("[\(check.status.rawValue)] \(check.name): \(check.detail)")
        }
    }

    private static func initConfig(arguments: [String]) throws {
        let parser = ArgumentParser(arguments)
        let path = parser.value(for: "--output") ?? parser.value(for: "--config") ?? EdgeAIConfigurationStore.defaultPath
        let configuration = EdgeAIConfiguration(
            inputPaths: parser.values(for: "--input"),
            embeddingModel: parser.value(for: "--embedding") ?? EdgeAIConfiguration.default.embeddingModel,
            generation: GenerationConfiguration(
                llamaServerURL: parser.value(for: "--llama-server"),
                modelPath: parser.value(for: "--model"),
                host: parser.value(for: "--host") ?? EdgeAIConfiguration.default.generation.host,
                port: parser.intValue(for: "--port") ?? EdgeAIConfiguration.default.generation.port,
                contextSize: parser.intValue(for: "--context-size") ?? EdgeAIConfiguration.default.generation.contextSize
            )
        )
        try EdgeAIConfigurationStore.save(configuration, to: URL(fileURLWithPath: path))
        print("Created configuration: \(path)")
    }

    private static func showConfig(arguments: [String]) throws {
        let parser = ArgumentParser(arguments)
        let configuration = try loadConfiguration(parser: parser)
        try printJSON(configuration)
    }

    private static func modelInfo(arguments: [String]) throws {
        let parser = ArgumentParser(arguments)
        let configuration = try loadConfiguration(parser: parser)
        let modelPath = parser.value(for: "--model") ?? configuration.generation.modelPath
        let json = parser.hasFlag("--json")

        guard let modelPath, !modelPath.isEmpty else {
            throw CLIError.message("No model path configured. Pass --model <path> or set generation.modelPath in config.")
        }

        let url = URL(fileURLWithPath: modelPath)
        let exists = FileManager.default.fileExists(atPath: modelPath)
        let sizeBytes = try? FileManager.default.attributesOfItem(atPath: modelPath)[.size] as? UInt64
        let response = ModelInfoResponse(
            path: modelPath,
            exists: exists,
            sizeBytes: sizeBytes ?? nil,
            fileExtension: url.pathExtension,
            recommendedServerURL: configuration.generation.effectiveServerURL
        )

        if json {
            try printJSON(response)
        } else {
            print("Model: \(response.path)")
            print("Exists: \(response.exists)")
            print("Size: \(format(bytes: response.sizeBytes))")
            print("Extension: \(response.fileExtension)")
            print("Server URL: \(response.recommendedServerURL)")
        }
    }

    private static func llamaCommand(arguments: [String]) throws {
        let parser = ArgumentParser(arguments)
        var configuration = try loadConfiguration(parser: parser)
        let executable = parser.value(for: "--llama-executable") ?? "llama-server"

        if let model = parser.value(for: "--model") {
            configuration.generation.modelPath = model
        }
        if let host = parser.value(for: "--host") {
            configuration.generation.host = host
        }
        if let port = parser.intValue(for: "--port") {
            configuration.generation.port = port
        }
        if let contextSize = parser.intValue(for: "--context-size") {
            configuration.generation.contextSize = contextSize
        }

        let command = configuration.generation.llamaServerCommand(executable: executable)
        if parser.hasFlag("--json") {
            try printJSON(LlamaCommandResponse(command: command, serverURL: configuration.generation.effectiveServerURL))
        } else {
            print(shellQuoted(command))
            print("Server URL: \(configuration.generation.effectiveServerURL)")
        }
    }

    private static func printHelp() {
        print("""
        edgeai — privacy-first offline RAG engine for local documents

        Commands:
          edgeai index --input <path> [--input <path>] [--output .edgeai/index.json]
          edgeai ask --question "What are the action items?" [--index .edgeai/index.json]
          edgeai search --query "thermal safeguards" [--index .edgeai/index.json]
          edgeai inspect [--index .edgeai/index.json]
          edgeai benchmark --input <path> [--query "..."]
          edgeai resources
          edgeai doctor [--config .edgeai/config.json]
          edgeai model-info [--model ./models/model.gguf]
          edgeai llama-command [--model ./models/model.gguf]
          edgeai init-config [--output .edgeai/config.json]
          edgeai show-config [--config .edgeai/config.json]
          edgeai version

        Optional:
          --config .edgeai/config.json             Load JSON configuration. CLI flags override config values.
          --embedding hash|natural                 Embedding backend for new indexes.
          --llama-server http://127.0.0.1:8080  Use a local llama.cpp server instead of the extractive fallback.
          --model ./models/model.gguf            Local GGUF model path metadata.
          --host 127.0.0.1                       llama.cpp host.
          --port 8080                            llama.cpp port.
          --context-size 4096                    llama.cpp context size.
          --llama-executable llama-server        llama.cpp server executable.
          --top-k 5                              Number of chunks to retrieve.
          --min-score 0.01                       Minimum cosine-similarity score.
          --json                                 Emit machine-readable JSON.
          --require-index                        Make doctor fail if the configured index is missing.
          --target-words 180                     Chunk size during indexing.
          --overlap-words 36                     Chunk overlap during indexing.
          --max-input-mb 50                      Maximum total input size during indexing.
          --max-resident-mb 2048                 Optional process resident-memory ceiling.
          --max-tokens 512                       Generation token cap for llama.cpp.
          --temperature 0.2                      Generation temperature for llama.cpp.
          --iterations 25                        Retrieval benchmark iterations.
        """)
    }

    private static func printCitations(_ citations: [RetrievedChunk], includePreview: Bool = false) {
        for (index, citation) in citations.enumerated() {
            let score = String(format: "%.3f", citation.score)
            print("[\(index + 1)] \(citation.chunk.title) (\(score)) — \(citation.chunk.sourcePath)")
            if includePreview {
                print("    \(citation.chunk.text.prefix(240))")
            }
        }
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard let output = String(data: data, encoding: .utf8) else {
            throw CLIError.message("Could not encode JSON output.")
        }
        print(output)
    }

    private static func format(milliseconds: Double) -> String {
        if milliseconds < 1_000 {
            return "\(String(format: "%.2f", milliseconds)) ms"
        }
        return "\(String(format: "%.2f", milliseconds / 1_000)) sec"
    }

    private static func format(bytes: UInt64?) -> String {
        guard let bytes else {
            return "unavailable"
        }
        return format(bytes: bytes)
    }

    private static func format(bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        return "\(String(format: "%.2f", value)) \(units[unitIndex])"
    }

    private static func elapsedMilliseconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    private static func shellQuoted(_ arguments: [String]) -> String {
        arguments.map { argument in
            if argument.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\"$`"))) == nil {
                return argument
            }
            return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }

    private static func loadConfiguration(parser: ArgumentParser) throws -> EdgeAIConfiguration {
        let path = parser.value(for: "--config") ?? EdgeAIConfigurationStore.defaultPath
        let url = URL(fileURLWithPath: path)
        return try EdgeAIConfigurationStore.loadIfPresent(from: url) ?? .default
    }

    private static func resourceGuard(
        parser: ArgumentParser,
        configuration: EdgeAIConfiguration,
        maxInputMB: Int? = nil
    ) -> ResourceGuard {
        let configuredMaxResidentMB = parser.value(for: "--max-resident-mb").flatMap { UInt64($0) }
            ?? configuration.resources.maxResidentMB

        return ResourceGuard(
            budget: ResourceBudget(
                maxInputBytes: (maxInputMB ?? configuration.resources.maxInputMB) * 1024 * 1024,
                maxChunksPerPrompt: configuration.resources.maxChunksPerPrompt,
                reduceContextWhenThermalsElevated: configuration.resources.reduceContextWhenThermalsElevated,
                maxResidentMemoryBytes: configuredMaxResidentMB.map { $0 * 1024 * 1024 }
            )
        )
    }
}

struct ArgumentParser {
    let arguments: [String]

    init(_ arguments: [String]) {
        self.arguments = arguments
    }

    func value(for flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    func intValue(for flag: String) -> Int? {
        value(for: flag).flatMap(Int.init)
    }

    func floatValue(for flag: String) -> Float? {
        value(for: flag).flatMap(Float.init)
    }

    func doubleValue(for flag: String) -> Double? {
        value(for: flag).flatMap(Double.init)
    }

    func values(for flag: String) -> [String] {
        arguments.indices.compactMap { index in
            guard arguments[index] == flag,
                  arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
    }

    func hasFlag(_ flag: String) -> Bool {
        arguments.contains(flag)
    }

    var positionalArguments: [String] {
        var result: [String] = []
        var skipNext = false
        let valueFlags: Set<String> = [
            "--input", "--output", "--target-words", "--overlap-words", "--index",
            "--question", "--query", "--top-k", "--min-score", "--llama-server",
            "--max-input-mb", "--max-resident-mb", "--max-tokens", "--temperature", "--iterations",
            "--embedding",
            "--config", "--model", "--host", "--port", "--context-size", "--llama-executable"
        ]

        for argument in arguments {
            if skipNext {
                skipNext = false
                continue
            }
            if valueFlags.contains(argument) {
                skipNext = true
                continue
            }
            if argument.hasPrefix("--") {
                continue
            }
            result.append(argument)
        }

        return result
    }
}

struct IndexCommandResponse: Codable {
    let indexPath: String
    let manifest: IndexManifest
}

struct AskCommandResponse: Codable {
    let question: String
    let answer: String
    let retrievalMilliseconds: Double
    let citations: [CitationResponse]

    init(question: String, result: RAGAnswer) {
        self.question = question
        self.answer = result.answer
        self.retrievalMilliseconds = result.retrievalMilliseconds
        self.citations = result.citations.map(CitationResponse.init)
    }
}

struct SearchCommandResponse: Codable {
    let query: String
    let citations: [CitationResponse]
}

struct CitationResponse: Codable {
    let title: String
    let sourcePath: String
    let chunkIndex: Int
    let score: Float
    let text: String

    init(_ retrievedChunk: RetrievedChunk) {
        self.title = retrievedChunk.chunk.title
        self.sourcePath = retrievedChunk.chunk.sourcePath
        self.chunkIndex = retrievedChunk.chunk.chunkIndex
        self.score = retrievedChunk.score
        self.text = retrievedChunk.chunk.text
    }
}

struct BenchmarkCommandResponse: Codable {
    let query: String
    let iterations: Int
    let manifest: IndexManifest
    let buildMetrics: IndexBuildMetrics
    let retrieval: LatencySummary
    let resourcesBefore: SystemResourceSnapshot
    let resourcesAfter: SystemResourceSnapshot
}

struct ModelInfoResponse: Codable {
    let path: String
    let exists: Bool
    let sizeBytes: UInt64?
    let fileExtension: String
    let recommendedServerURL: String
}

struct LlamaCommandResponse: Codable {
    let command: [String]
    let serverURL: String
}

enum DoctorStatus: String, Codable {
    case pass
    case warn
    case fail
}

struct DoctorCheck: Codable {
    let name: String
    let status: DoctorStatus
    let detail: String
}

struct DoctorReport: Codable {
    let overallStatus: DoctorStatus
    let checks: [DoctorCheck]

    init(checks: [DoctorCheck]) {
        self.checks = checks
        if checks.contains(where: { $0.status == .fail }) {
            self.overallStatus = .fail
        } else if checks.contains(where: { $0.status == .warn }) {
            self.overallStatus = .warn
        } else {
            self.overallStatus = .pass
        }
    }

    var hasFailures: Bool {
        overallStatus == .fail
    }
}

struct LatencySummary: Codable {
    let minimumMilliseconds: Double
    let averageMilliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double

    init(milliseconds: [Double]) {
        let sorted = milliseconds.sorted()
        self.minimumMilliseconds = sorted.first ?? 0
        self.maximumMilliseconds = sorted.last ?? 0
        self.averageMilliseconds = sorted.reduce(0, +) / Double(max(sorted.count, 1))
        let p95Index = min(sorted.count - 1, Int((Double(sorted.count - 1) * 0.95).rounded(.up)))
        self.p95Milliseconds = sorted.isEmpty ? 0 : sorted[p95Index]
    }
}

enum CLIError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message):
            return message
        }
    }
}
