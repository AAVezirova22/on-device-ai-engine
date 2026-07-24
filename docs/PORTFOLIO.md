# Portfolio Notes

Use this wording only after you can explain the architecture in `docs/LEARNING_GUIDE.md`.

## LinkedIn / Upwork project summary

Built a native Swift offline RAG engine for macOS that indexes local Markdown, text, and PDF files, retrieves relevant context using local vector search, and answers with source citations through either a deterministic offline fallback or a local llama.cpp model server. Added thermal-aware resource safeguards and a packaged macOS menu-bar clipboard summarization assistant.

## Technical bullets

- Designed a modular local AI pipeline with separate document loading, chunking, embedding, vector retrieval, prompt construction, and LLM backend layers.
- Implemented local retrieval with two embedding backends: deterministic hash embeddings for reproducible tests and Apple NaturalLanguage semantic embeddings for on-device semantic search.
- Added a `llama.cpp` HTTP adapter so the same RAG engine can use quantized local models running on-device.
- Built and packaged an unsigned macOS menu-bar app using AppKit and Carbon that summarizes clipboard text without sending content to external services.
- Added configurable global hotkey support through JSON configuration.
- Added a menu-bar Preferences UI for embedding and hotkey settings.
- Added resource guardrails for maximum input size and thermal-state-aware context reduction.
- Added JSON configuration support and release/smoke verification scripts for repeatable operation.
- Added local GGUF model metadata and llama-server command generation for operational llama.cpp workflows.
- Wrote unit tests covering embeddings, chunking, retrieval, and RAG citation behavior.

## Demo script

```bash
swift test
swift run edgeai index --input sample_docs --output .edgeai/index.json
swift run edgeai ask --question "What are the action items?"
```

Expected result: the assistant extracts action items from `sample_docs/meeting-notes.md` and prints local source citations.

## Be precise in interviews

Say this:

> The project supports deterministic hash embeddings and Apple NaturalLanguage semantic embeddings. The architecture is intentionally designed so I can add MLX Swift, Core ML, or llama.cpp embeddings later.

Do not say this yet:

> I implemented custom Metal inference kernels.

That would only be true after adding real Metal/MLX inference or llama.cpp native bindings and benchmarks.

## Next milestones

1. Replace hash embeddings with a real local embedding model.
2. Add direct llama.cpp C/C++ interoperability instead of only the HTTP adapter.
3. Add benchmark scripts for indexing throughput, query latency, and memory use.
4. Add richer Preferences controls for all CLI configuration fields.
5. Add iOS support with Core ML or MLX-compatible model execution.
