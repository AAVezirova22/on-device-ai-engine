# Product Planning Notes

The team wants a privacy-first assistant that can summarize local documents without sending data to a cloud service.

Action items:

- Build a local document index for markdown, text, and PDFs.
- Add retrieval over vector embeddings before calling the language model.
- Add safeguards so large indexing jobs do not exceed the memory budget.
- Prototype a global macOS hotkey that summarizes clipboard text.

The first version should run fully offline with a deterministic fallback, then support local llama.cpp models when available.
