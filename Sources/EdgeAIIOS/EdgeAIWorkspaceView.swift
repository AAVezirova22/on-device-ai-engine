import EdgeAIEngine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

public struct EdgeAIWorkspaceView: View {
    @StateObject private var viewModel: EdgeAIWorkspaceViewModel
    @State private var isImporterPresented = false

    public init(configuration: EdgeAIConfiguration = .default) {
        _viewModel = StateObject(wrappedValue: EdgeAIWorkspaceViewModel(configuration: configuration))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Documents") {
                    Button("Import Documents") {
                        isImporterPresented = true
                    }

                    if viewModel.selectedPaths.isEmpty {
                        Text("No documents selected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.selectedPaths, id: \.self) { path in
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                        }
                    }
                }

                Section("Index") {
                    Button("Build Local Index") {
                        Task { await viewModel.buildIndex() }
                    }
                    .disabled(viewModel.selectedPaths.isEmpty || viewModel.isWorking)

                    if let manifest = viewModel.manifest {
                        LabeledContent("Documents", value: "\(manifest.documentCount)")
                        LabeledContent("Chunks", value: "\(manifest.chunkCount)")
                        LabeledContent("Embedding", value: manifest.embeddingModel)
                    }
                }

                Section("Ask") {
                    TextField("Question", text: $viewModel.question, axis: .vertical)

                    Button("Ask Local Engine") {
                        Task { await viewModel.ask() }
                    }
                    .disabled(viewModel.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isWorking || viewModel.manifest == nil)

                    if !viewModel.answer.isEmpty {
                        Text(viewModel.answer)
                            .textSelection(.enabled)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section("Status") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("On-Device AI")
            .toolbar {
                if viewModel.isWorking {
                    ProgressView()
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.plainText, .pdf, .text, .data],
                allowsMultipleSelection: true
            ) { result in
                viewModel.handleImportResult(result)
            }
        }
    }
}

@MainActor
public final class EdgeAIWorkspaceViewModel: ObservableObject {
    @Published public private(set) var selectedPaths: [String] = []
    @Published public private(set) var manifest: IndexManifest?
    @Published public private(set) var answer = ""
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isWorking = false
    @Published public var question = ""

    private var configuration: EdgeAIConfiguration
    private var storedIndex: StoredIndex?

    public init(configuration: EdgeAIConfiguration = .default) {
        self.configuration = configuration
    }

    public func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            selectedPaths = urls.map(\.path)
            configuration.inputPaths = selectedPaths
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func buildIndex() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let model = try EmbeddingModelFactory.make(identifier: configuration.embeddingModel)
            let result = try IndexBuilder.build(
                inputURLs: selectedPaths.map { URL(fileURLWithPath: $0) },
                embeddingModel: model,
                chunking: configuration.chunking,
                resourceGuard: ResourceGuard(budget: configuration.resources.budget)
            )
            storedIndex = result.storedIndex
            manifest = result.storedIndex.manifest
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func ask() async {
        guard let storedIndex else {
            errorMessage = "Build an index before asking questions."
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let embeddingModel = try EmbeddingModelFactory.make(
                identifier: storedIndex.manifest.embeddingModel,
                dimensions: storedIndex.index.embeddingDimensions
            )
            let engine = RAGEngine(
                index: storedIndex.index,
                embeddingModel: embeddingModel,
                llm: ExtractiveLocalLLM(),
                resourceGuard: ResourceGuard(budget: configuration.resources.budget)
            )
            let response = try await engine.answer(
                question: question,
                options: RAGOptions(
                    topK: configuration.retrieval.topK,
                    minimumScore: configuration.retrieval.minimumScore,
                    searchMode: configuration.retrieval.searchMode,
                    scoringBackend: configuration.retrieval.scoringBackend,
                    llmOptions: LLMOptions(
                        maxTokens: configuration.generation.maxTokens,
                        temperature: configuration.generation.temperature
                    )
                )
            )
            answer = response.answer
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
