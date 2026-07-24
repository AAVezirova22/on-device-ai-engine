# On-Device AI Engine

Native Swift local AI engine for privacy-first document Q&A and productivity workflows on macOS.

The project indexes local Markdown, text, and PDF files, retrieves relevant passages with local vector search, and answers with source citations through either:

- a deterministic offline fallback, or
- a local `llama.cpp` server.

It also includes a macOS global-hotkey clipboard summarization demo.

## Quick start

```bash
swift test
swift run edgeai index --input sample_docs --output .edgeai/index.json
swift run edgeai inspect --index .edgeai/index.json
swift run edgeai search --index .edgeai/index.json --query "thermal safeguards"
swift run edgeai ask --index .edgeai/index.json --question "What are the action items?"
swift run edgeai benchmark --input sample_docs --query "thermal safeguards"
```

Run the full smoke test:

```bash
scripts/smoke-test.sh
```

Run the release gate:

```bash
scripts/release-check.sh
```

Package the unsigned macOS menu-bar app:

```bash
scripts/package-macos-app.sh
open "dist/On-Device AI Engine.app"
```

## Main commands

```bash
edgeai index   --input <path> [--output .edgeai/index.json]
edgeai inspect [--index .edgeai/index.json] [--json]
edgeai search  --query "..." [--index .edgeai/index.json] [--json]
edgeai ask     --question "..." [--index .edgeai/index.json] [--json]
edgeai benchmark --input <path> [--query "..."] [--json]
edgeai resources [--json]
edgeai doctor [--config .edgeai/config.json] [--json]
edgeai model-info [--model ./models/model.gguf] [--json]
edgeai llama-command [--model ./models/model.gguf] [--json]
edgeai init-config [--output .edgeai/config.json]
edgeai show-config [--config .edgeai/config.json]
edgeai version
```

Configuration files are supported:

```bash
swift run edgeai init-config --output .edgeai/config.json --input sample_docs
swift run edgeai index --config .edgeai/config.json
swift run edgeai ask --config .edgeai/config.json --question "What are the action items?"
```

Precedence is: built-in defaults, then config file, then explicit CLI flags.

Use Apple’s local NaturalLanguage embeddings for semantic retrieval:

```bash
swift run edgeai index \
  --input sample_docs \
  --output .edgeai/natural-index.json \
  --embedding natural
```

The default `hash` backend is deterministic and portable. The `natural` backend is semantic and fully on-device, but depends on Apple’s NaturalLanguage embeddings being available on the machine.

The menu-bar app hotkey is configurable in `.edgeai/config.json`:

```json
{
  "hotkey": {
    "key": "s",
    "modifiers": ["control", "option", "command"]
  }
}
```

Use a local model:

```bash
swift run edgeai llama-command --model ./models/model.gguf
swift run edgeai ask \
  --index .edgeai/index.json \
  --question "Summarize the local documents" \
  --llama-server http://127.0.0.1:8080
```

## What is implemented

- Native Swift package with library, CLI, and hotkey/menu-bar app targets.
- Unsigned macOS menu-bar app packaging for the clipboard assistant.
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
- Local GGUF model metadata and llama-server command generation.
- Deterministic offline fallback for demos and tests.
- Thermal-aware retrieval limits.
- Runtime resource snapshots for thermal state and resident memory.
- Benchmark command for build/retrieval latency.
- Doctor command for readiness checks.
- Project configuration file support.
- Maximum input-size guard.
- JSON output for CLI automation.
- Unit tests and smoke-test script.

## Documentation

- [Product documentation](docs/PRODUCT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Operations guide](docs/OPERATIONS.md)
- [Learning guide](docs/LEARNING_GUIDE.md)
- [Production readiness](docs/PRODUCTION_READINESS.md)
- [Release guide](docs/RELEASE.md)
- [Portfolio notes](docs/PORTFOLIO.md)

## Project structure

```text
Sources/EdgeAIEngine       Core RAG, embeddings, indexing, storage, LLM adapters
Sources/EdgeAIEngineCLI    Command-line interface
Sources/EdgeAIHotkey       macOS menu-bar clipboard assistant
Tests/EdgeAIEngineTests    Unit tests
docs                       Product, architecture, learning, and operations docs
sample_docs                Demo corpus
scripts                    Smoke test and operational helpers
```

## Important scope note

This repository currently implements the native Swift RAG engine and local llama.cpp server integration. It does not yet implement custom Metal kernels, direct C++ llama.cpp bindings, or MLX Swift inference. Those are documented roadmap items, not current claims.
