# Learning Guide

Use this project to learn the system in layers.

## 1. Retrieval-Augmented Generation

Start with `RAGEngine.answer(question:topK:)`.

The core idea is simple:

1. Embed the user question.
2. Search local document chunks by vector similarity.
3. Put the best chunks into the prompt.
4. Ask the local model to answer only from that context.

The important engineering decision is separation: retrieval should work even if the model backend changes.

## 2. Embeddings

Open `HashEmbeddingModel`.

The default implementation uses feature hashing:

- tokenize text,
- hash each token into a fixed vector slot,
- add `+1` or `-1`,
- L2-normalize the vector.

This is educational and dependency-free.

The project also includes `NaturalLanguageEmbeddingModel`, which uses Apple’s local NaturalLanguage embeddings. That backend is semantic and still on-device:

```bash
swift run edgeai index --input sample_docs --embedding natural
```

A larger production build could add MLX, Core ML, or llama.cpp embeddings behind the same `EmbeddingModel` protocol.

## 3. Vector search

Open `VectorIndex`.

The index is an array of:

- document chunk,
- embedding vector.

Search computes dot product between the query vector and every stored vector. Because vectors are normalized, dot product is cosine similarity.

This is exact search. For larger corpora, replace it with approximate nearest-neighbor indexing.

## 4. Local generation

Open `LocalLLM`.

The app has two backends:

- `ExtractiveLocalLLM`, which lets the project run without a model.
- `LlamaCppServerClient`, which calls a local `llama.cpp` server.

This is the right abstraction point for adding:

- direct C++ llama.cpp bindings,
- MLX Swift inference,
- Core ML model execution.

The CLI can also generate the local server command:

```bash
swift run edgeai llama-command --model ./models/model.gguf
```

## 5. macOS integration

Open `Sources/EdgeAIHotkey/main.swift`.

The hotkey target registers Control+Option+Command+S using Carbon and reads text from the macOS clipboard. It summarizes that text and writes the result back to the clipboard.

This proves the system-wide assistant pattern without needing Accessibility automation in the first version.

## 6. Resource management

Open `ResourceGuard`.

Local AI apps fail when they ignore device limits. This project starts with:

- input-size caps,
- thermal-state checks,
- context reduction under serious thermal pressure.

The next level is measuring model memory, KV-cache growth, and Metal command-buffer duration.
