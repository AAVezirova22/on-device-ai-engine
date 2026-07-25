# On-Device AI Engine

Native Swift local AI engine for privacy-first document Q&A and productivity workflows on Apple platforms.

The project indexes local Markdown, text, and PDF files, retrieves relevant passages with local vector search, and answers with source citations through either:

- a deterministic offline fallback, or
- a local `llama.cpp` server.

It also includes a macOS menu-bar assistant with a configurable global hotkey for clipboard summarization and a SwiftUI iOS workspace view for embedding the engine in an iOS app.

## Quick start

First, open Terminal in the project folder:

```bash
cd (path)/On-DeviceAiEngine
```

Then use the simple workflow with any folder containing Markdown, text, or PDF files:

```bash
swift run edgeai setup ~/Documents/Notes (example path)
swift run edgeai ask "What are the action items?"
swift run edgeai find "project risks"
swift run edgeai files
```

That is the normal user path:

1. `setup` teaches the app which folder to use and builds the local index.
2. `ask` answers a question from the indexed files.
3. `find` shows matching source passages.
4. `files` shows what was indexed.

Run tests only when you are checking the code:

```bash
swift test
```

Run the full local smoke test:

```bash
scripts/smoke-test.sh
```

Run the release gate:

```bash
scripts/release-check.sh
```

Package the macOS menu-bar app:

```bash
scripts/package-macos-app.sh
open "dist/On-Device AI Engine.app"
```

## Main commands

```bash
edgeai setup <path>
edgeai ask "..."
edgeai find "..."
edgeai files
```

Advanced commands:

```bash
edgeai index --input <path> [--output .edgeai/index.json]
edgeai inspect [--index .edgeai/index.json] [--json]
edgeai search --query "..." [--index .edgeai/index.json] [--json]
edgeai ask --question "..." [--index .edgeai/index.json] [--json]
edgeai benchmark --input <path> [--query "..."] [--json]
edgeai resources [--json]
edgeai runtimes [--json]
edgeai doctor [--config .edgeai/config.json] [--json]
edgeai model-info [--model ./models/model.gguf] [--json]
edgeai llama-command [--model ./models/model.gguf] [--json]
edgeai init-config [--output .edgeai/config.json]
edgeai show-config [--config .edgeai/config.json]
edgeai version
```

Configuration files are supported:

```bash
swift run edgeai init-config --output .edgeai/config.json --input ~/Documents/Notes
swift run edgeai index --config .edgeai/config.json
swift run edgeai ask --config .edgeai/config.json --question "What are the action items?"
```

Precedence is: built-in defaults, then config file, then explicit CLI flags.

## Retrieval and acceleration

Embedding backends:

- `hash`: deterministic local feature-hashing backend for reproducible tests and offline fallback.
- `natural`: Apple NaturalLanguage semantic embeddings when available on the machine.

Search modes:

- `exact`: linear scan over all vectors.
- `approximate`: locality-sensitive hashing candidate selection, then exact scoring inside the candidate set.
- `auto`: exact for smaller indexes, approximate for larger indexes.

Scoring backends:

- `swift`: pure Swift dot product.
- `native-cxx`: C++ dot-product kernel exposed to Swift through SwiftPM.
- `metal`: runtime Metal compute kernel.
- `auto`: Metal when available, otherwise native C++.

Example:

```bash
swift run edgeai index \
  --input ~/Documents/Notes \
  --output .edgeai/natural-index.json \
  --embedding natural

swift run edgeai search \
  --index .edgeai/natural-index.json \
  --query "thermal safeguards" \
  --search-mode approximate \
  --scoring metal
```

## Local model usage

Generate a local `llama-server` command:

```bash
swift run edgeai llama-command --model ./models/model.gguf
```

Ask through that local server:

```bash
swift run edgeai ask \
  --index .edgeai/index.json \
  --question "Summarize the local documents" \
  --llama-server http://127.0.0.1:8080
```

By default, the engine does not make network requests. A request is made only when you explicitly configure a `--llama-server` URL.

Inspect local runtime support in the current build:

```bash
swift run edgeai runtimes
```

## What is implemented

- Native Swift package with library, CLI, and hotkey/menu-bar app targets.
- SwiftUI iOS workspace target for importing documents, building an index, and asking local questions.
- Native C++ vector scoring kernel integrated through SwiftPM.
- Runtime Metal compute scoring backend.
- Exact and approximate vector search.
- macOS menu-bar app packaging for the clipboard assistant.
- Configurable menu-bar app hotkey.
- Launch at Login menu support for signed builds.
- Privacy and permissions onboarding in the menu-bar app.
- Preferences UI for embedding and hotkey settings.
- Offline ingestion for `.md`, `.markdown`, `.txt`, `.text`, and `.pdf`.
- Recursive chunking with overlap.
- Local vector index persisted as JSON.
- Embedding backends: deterministic hash and Apple NaturalLanguage semantic embeddings.
- Index schema validation and source-document metadata.
- Retrieval-only search command for debugging answer quality.
- RAG prompt construction with citations.
- llama.cpp HTTP adapter.
- Runtime registry for extractive, llama.cpp server, native llama.cpp, and MLX Swift integration paths.
- Local GGUF model metadata and llama-server command generation.
- Deterministic offline fallback for tests and model-free use.
- Thermal-aware retrieval limits.
- Runtime resource snapshots for thermal state and resident memory.
- Benchmark command for build/retrieval latency.
- Doctor command for readiness checks.
- Project configuration file support.
- Maximum input-size guard.
- JSON output for CLI automation.
- Unit tests, smoke test, release check, packaging script, and signing/notarization script.

## Documentation

- [Product documentation](docs/PRODUCT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Operations guide](docs/OPERATIONS.md)
- [Release guide](docs/RELEASE.md)

## Project structure

```text
Sources/EdgeAIEngine          Core RAG, embeddings, indexing, storage, LLM adapters
Sources/EdgeAINativeKernels   C++ scoring kernels used by Swift
Sources/EdgeAIEngineCLI       Command-line interface
Sources/EdgeAIHotkey          macOS menu-bar clipboard assistant
Sources/EdgeAIIOS             SwiftUI iOS workspace UI
Tests/EdgeAIEngineTests       Unit tests
docs                          Product, architecture, learning, and operations docs
scripts                       Smoke test and operational helpers
```
