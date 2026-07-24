# Architecture

## System overview

On-Device AI Engine is organized as a native Swift package with three executable surfaces:

1. `EdgeAIEngine`: reusable library containing document loading, chunking, embeddings, vector search, index persistence, RAG orchestration, resource guardrails, and LLM adapters.
2. `EdgeAINativeKernels`: C++ kernel target used by Swift for native vector scoring.
3. `EdgeAIIOS`: SwiftUI workspace target for importing documents, building a local index, and asking local questions from an iOS app shell.
4. `edgeai`: command-line interface for indexing, inspecting, searching, and asking questions.
5. `edgeai-hotkey`: macOS helper that registers a system-wide hotkey and summarizes clipboard text.

The core design rule is separation of concerns. Retrieval, generation, storage, acceleration, and OS integration are independent modules. This keeps the engine usable with deterministic offline generation, local semantic embeddings, C++ scoring, Metal scoring, and a local llama.cpp server adapter.

## Runtime data flow

```text
Local files (.md, .txt, .pdf)
   ↓
DocumentLoader
   ↓
RecursiveChunker
   ↓
EmbeddingModel
   ↓
VectorIndex
   ↓
IndexStore JSON file
   ↓
RAGEngine.retrieve / RAGEngine.answer
   ↓
PromptBuilder
   ↓
LocalLLM backend
   ↓
Answer with citations
```

## Source layout

```text
Sources/
  EdgeAINativeKernels/
    EdgeAINativeKernels.cpp
    include/EdgeAINativeKernels.h
  EdgeAIEngine/
    DocumentLoader.swift
    EdgeAIConfiguration.swift
    EmbeddingModel.swift
    EngineVersion.swift
    IndexBuilder.swift
    IndexStore.swift
    LocalDocument.swift
    LocalLLM.swift
    LocalRuntime.swift
    RAGEngine.swift
    RecursiveChunker.swift
    ResourceGuard.swift
    SourceDocumentMetadata.swift
    SystemResourceSnapshot.swift
    VectorIndex.swift
  EdgeAIEngineCLI/
    main.swift
  EdgeAIHotkey/
    main.swift
  EdgeAIIOS/
    EdgeAIWorkspaceView.swift
Tests/
  EdgeAIEngineTests/
    EdgeAIEngineTests.swift
docs/
scripts/
```

## Core files

### `LocalDocument.swift`

Defines the basic domain models:

- `LocalDocument`: full source file after text extraction.
- `DocumentChunk`: chunked passage used for retrieval.
- `RetrievedChunk`: retrieval result plus similarity score.

### `DocumentLoader.swift`

Loads supported local document types:

- Markdown: `.md`, `.markdown`
- Plain text: `.txt`, `.text`
- PDF: `.pdf`, via PDFKit when available

It can load individual files or recursively enumerate directories while skipping hidden files.

### `EdgeAIConfiguration.swift`

Defines the JSON configuration model used by the CLI.

Configuration covers:

- index path,
- input paths,
- chunking,
- retrieval,
- generation backend/options,
- resource limits,
- menu-bar app hotkey.

`EdgeAIConfigurationStore` handles JSON load/save and optional default loading from `.edgeai/config.json`.

### `RecursiveChunker.swift`

Splits documents into overlapping word chunks.

Why overlap matters: if a relevant idea crosses a chunk boundary, overlap helps preserve enough context for retrieval and generation.

### `EmbeddingModel.swift`

Defines the embedding boundary:

```swift
public protocol EmbeddingModel {
    var dimensions: Int { get }
    func embed(_ text: String) -> [Float]
}
```

Implemented backends:

- `HashEmbeddingModel`: feature hashing with L2 normalization. It is dependency-free, deterministic, and portable.
- `NaturalLanguageEmbeddingModel`: uses Apple’s local NaturalLanguage sentence/word embeddings for semantic retrieval when available.

The hash backend is useful for learning, tests, and reproducible fallback behavior. The NaturalLanguage backend is the first real semantic local embedding option in the project.

New indexes record the embedding backend in the manifest. Query commands recreate the backend from the manifest so an index built with `natural` is queried with `natural`, and an index built with `hash` is queried with `hash`.

### `VectorIndex.swift`

Stores `IndexedChunk` records:

- chunk metadata/text,
- embedding vector.

Search embeds the query and computes dot product against stored vectors. Because vectors are normalized, dot product approximates cosine similarity.

Implemented search modes:

- `exact`: scans every indexed vector.
- `approximate`: uses deterministic locality-sensitive hashing to select candidates, then scores candidates exactly.
- `auto`: exact search for smaller indexes, approximate candidate search for larger indexes.

Implemented scoring backends:

- `swift`: pure Swift dot product.
- `native-cxx`: C++ dot-product kernel exposed to Swift.
- `metal`: runtime Metal compute kernel.
- `auto`: Metal when available, otherwise native C++.

### `EdgeAINativeKernels`

Provides the C++ scoring function imported into Swift:

```cpp
float edgeai_dot_product_f32(const float *left, const float *right, int32_t count);
```

The Swift layer uses this through `NativeVectorKernels.dot`.

### `IndexBuilder.swift`

High-level indexing pipeline:

1. load documents,
2. enforce resource budget,
3. chunk documents,
4. embed chunks,
5. build vector index,
6. create manifest,
7. record build metrics.

`IndexBuildResult` returns the `StoredIndex` and timing metrics.

### `IndexStore.swift`

Persists and loads indexes as JSON.

The manifest includes:

- schema version,
- engine version,
- embedding model,
- embedding dimensions,
- document count,
- chunk count,
- total content bytes,
- chunking configuration,
- build metrics,
- source document metadata.

`IndexStore.validate` rejects corrupted or incompatible indexes.

### `SourceDocumentMetadata.swift`

Stores source-level metadata:

- path,
- title,
- byte count,
- content fingerprint.

The fingerprint is currently a stable FNV-1a hash of extracted text. It is used for change detection and auditability, not cryptographic security.

### `RAGEngine.swift`

Coordinates retrieval and generation.

`retrieve(question:topK:minimumScore:searchMode:scoringBackend:)` returns matching chunks without calling a model.

`answer(question:options:)`:

1. checks resource guardrails,
2. retrieves relevant chunks,
3. builds a grounded prompt,
4. calls the configured `LocalLLM`,
5. returns answer, citations, and retrieval timing.

### `EdgeAIIOS/EdgeAIWorkspaceView.swift`

Provides a SwiftUI workspace UI and `EdgeAIWorkspaceViewModel`.

The view model:

1. receives imported local document URLs,
2. builds an in-memory index with the shared `IndexBuilder`,
3. asks questions through the shared `RAGEngine`,
4. exposes status, manifest metadata, and answers to SwiftUI.

### `LocalLLM.swift`

Defines the model backend boundary:

```swift
public protocol LocalLLM {
    func complete(prompt: String, options: LLMOptions) async throws -> String
}
```

Implemented backends:

- `ExtractiveLocalLLM`: deterministic local fallback.
- `LlamaCppServerClient`: HTTP adapter for a local llama.cpp server.

### `LocalRuntime.swift`

Defines runtime capability reporting for:

- built-in extractive fallback,
- llama.cpp server mode,
- native llama.cpp build-time integration,
- MLX Swift build-time integration.

The CLI exposes these checks through `edgeai runtimes`, and `doctor` includes runtime status in its readiness report.

### `ResourceGuard.swift`

Protects the machine during local AI workloads:

- rejects oversized inputs,
- rejects new heavy work at critical thermal state,
- reduces retrieved context at serious thermal state,
- clamps retrieved chunk count.
- optionally rejects work when resident memory exceeds a configured ceiling.

### `SystemResourceSnapshot.swift`

Provides lightweight runtime telemetry:

- process thermal state,
- physical memory,
- resident memory for the current process when available.

This powers `edgeai resources` and benchmark output.

### `EngineVersion.swift`

Central version constants:

- engine version,
- index schema version.

## CLI architecture

`Sources/EdgeAIEngineCLI/main.swift` maps CLI commands onto library APIs.

Commands:

- `index`: build and save an index.
- `inspect`: validate and print index metadata.
- `search`: retrieve chunks without generation.
- `ask`: retrieve context and generate an answer.
- `benchmark`: measure index build and retrieval latency.
- `resources`: print thermal/memory resource snapshot.
- `runtimes`: print local runtime capability status.
- `doctor`: validate configuration, resource state, embedding backend, index integrity, and llama.cpp connectivity.
- `model-info`: inspect configured local model metadata.
- `llama-command`: generate a `llama-server` command from config/flags.
- `init-config`: write a starter JSON configuration.
- `show-config`: print the active configuration.
- `version`: print engine version.

Most commands support `--json` so the tool can be scripted from other software.

Configuration precedence is handled in the CLI layer:

```text
built-in defaults < config file < explicit CLI flags
```

## Menu-bar app and hotkey architecture

`Sources/EdgeAIHotkey/main.swift` is a macOS menu-bar utility:

1. creates an `NSStatusItem`,
2. exposes Summarize Clipboard, Preferences, Privacy & Permissions, Launch at Login, About, and Quit menu actions,
3. registers Control+Option+Command+S using Carbon,
4. reads text from `NSPasteboard.general`,
5. builds an in-memory one-document index,
6. uses the configured embedding backend and hotkey,
7. asks the engine to summarize and extract actions,
8. writes the answer back to the clipboard,
9. updates menu-bar status text.

`scripts/package-macos-app.sh` packages the release executable into a `.app` bundle with `LSUIElement` enabled so it behaves as a menu-bar utility.

The Preferences action is implemented with AppKit controls and writes `EdgeAIConfiguration` back to `.edgeai/config.json`, then re-registers the global hotkey.

For external distribution, the generated app still needs Developer ID code signing and notarization.

Launch at Login is implemented through `SMAppService.mainApp` from ServiceManagement and is intended for signed app bundles.

## Technology choices

### Swift

Used for native Apple-platform development, strong type safety, async support, and straightforward integration with AppKit/PDFKit.

### Swift Package Manager

Used to keep the project buildable from the terminal and easy to inspect.

### NaturalLanguage

Used for optional local semantic embeddings through Apple-provided on-device language resources.

### PDFKit

Used for local PDF text extraction on macOS.

### AppKit and Carbon

Used by the hotkey helper for clipboard access and global hotkey registration.

### ServiceManagement

Used by the menu-bar app for Launch at Login registration through `SMAppService.mainApp`.

### llama.cpp

Supported through HTTP server mode. This keeps model execution in a local `llama-server` process while the Swift engine handles retrieval, prompt assembly, configuration, and operational checks.

### Metal

Metal is used for vector dot-product scoring through a runtime compute pipeline. The scorer is selected with `--scoring metal`, or automatically when `--scoring auto` detects a usable Metal device.

## Privacy and security architecture

Default behavior is local-only:

- local files are read from disk,
- index is saved locally,
- fallback answers are generated locally,
- no network request is made by default.

The only model network path is explicit `--llama-server`. For private documents, use `127.0.0.1` only.

## Performance characteristics

Current complexity:

- indexing: O(number of chunks × embedding dimensions),
- exact retrieval: O(number of chunks × embedding dimensions),
- approximate retrieval: locality-sensitive hashing candidate lookup plus exact scoring inside the candidate set,
- storage: JSON, optimized for transparency rather than compactness.

This structure keeps the implementation inspectable while still supporting accelerated local retrieval paths.
