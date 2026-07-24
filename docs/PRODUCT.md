# Product Documentation

## Product name

On-Device AI Engine

## What it is

On-Device AI Engine is a privacy-first local AI productivity assistant for macOS. It indexes local documents, retrieves relevant passages, and uses a local language-model backend to answer questions, summarize text, or extract action items without sending private files to a cloud service.

The current implementation is a production-oriented native Swift foundation:

- command-line RAG engine,
- local document index,
- PDF/Markdown/text ingestion,
- source-cited answers,
- llama.cpp server integration,
- local GGUF model metadata and llama-server command generation,
- Apple NaturalLanguage semantic embeddings as an optional local retrieval backend,
- deterministic offline fallback,
- macOS global-hotkey clipboard summarization menu-bar app,
- packaged unsigned macOS app artifact,
- configurable global hotkey,
- Launch at Login support for signed builds,
- privacy and permissions onboarding,
- Preferences UI for embedding and hotkey settings,
- resource guardrails for memory and thermal pressure.
- resource and benchmark commands for operational visibility.
- doctor readiness checks for local setup validation.
- JSON configuration files for repeatable local workflows.

## Who it helps

### Freelancers and consultants

They can query project notes, contracts, specifications, or meeting notes locally. Sensitive client files stay on the device.

### Developers

They can index technical docs, architecture notes, TODO files, and code-adjacent Markdown, then ask questions with source citations.

### Students and researchers

They can load papers, lecture notes, and Markdown summaries into a local index and ask grounded questions.

### Privacy-sensitive teams

They can prototype AI workflows where documents cannot leave the device because of compliance, client confidentiality, or personal preference.

## Main use cases

### Local document Q&A

Index a folder of notes or PDFs and ask questions:

```bash
swift run edgeai index --input ~/Documents/ProjectNotes --output .edgeai/project.json
swift run edgeai ask --index .edgeai/project.json --question "What risks are mentioned in the planning docs?"
```

### Action-item extraction

Ask for follow-up work from meeting notes:

```bash
swift run edgeai ask --question "What are the action items?"
```

### Retrieval debugging

Before blaming the model, inspect what the retriever found:

```bash
swift run edgeai search --query "thermal safeguards" --top-k 5
```

### Clipboard summarization

Run the hotkey helper:

```bash
swift run edgeai-hotkey
```

Copy text from any app, press Control+Option+Command+S, and the summary is copied back to the clipboard.

## Privacy model

By default, the project uses local files and a deterministic local fallback. No network request is made unless the user explicitly passes `--llama-server`.

When `--llama-server` is used, requests go to the URL provided by the user. The recommended production configuration is a localhost-only llama.cpp server:

```bash
llama-server -m ./models/model.gguf --host 127.0.0.1 --port 8080
```

Do not point `--llama-server` at a remote service if the indexed documents are private.

## Current production boundary

Implemented:

- Native Swift package.
- Local file ingestion.
- Local vector index persisted as JSON.
- Schema/version validation for indexes.
- Manifest metadata with source document fingerprints.
- CLI commands for indexing, retrieval, answering, inspection, JSON output, and versioning.
- Unit tests and smoke-test script.
- Local llama.cpp server adapter.
- Model metadata and llama-server command generation commands.
- Unsigned macOS menu-bar app packaging.
- Configurable hotkey support through `.edgeai/config.json`.
- Launch at Login menu support through ServiceManagement.
- Privacy and permissions onboarding in the menu-bar app.
- Preferences UI that writes `.edgeai/config.json`.
- Runtime thermal/memory snapshots.
- Benchmark command for indexing and retrieval latency.
- Doctor command for config/index/backend readiness checks.
- Configuration file support with CLI override precedence.
- Optional Apple NaturalLanguage semantic embedding backend.

Not yet implemented:

- Direct C++ llama.cpp bindings.
- MLX Swift model execution.
- Custom Metal kernels.
- Approximate nearest-neighbor indexing.
- Signed and notarized macOS app bundle.
- iOS UI.

This distinction matters. The repo is useful and demonstrable now, but custom Metal/MLX inference should be treated as a future milestone unless those modules are added.
