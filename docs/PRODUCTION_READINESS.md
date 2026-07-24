# Production Readiness

This document defines what is production-ready in the current repository and what remains on the roadmap.

## Completed production-oriented capabilities

### Build and test automation

- SwiftPM package.
- Library target.
- CLI target.
- macOS hotkey/menu-bar target.
- Unsigned macOS `.app` packaging script for the menu-bar hotkey assistant.
- Developer ID signing/notarization script for credentialed distribution.
- Configurable menu-bar app hotkey through `.edgeai/config.json`.
- Launch at Login menu support through ServiceManagement.
- Privacy and permissions onboarding in the menu-bar app.
- Preferences UI for embedding and hotkey configuration.
- Unit tests for chunking, embeddings, retrieval, RAG answers, index metadata, index validation, and resource guardrails.
- Smoke-test script covering end-to-end CLI behavior.
- Release-check script covering tests, smoke test, release build, and release binary sanity checks.
- Benchmark command for indexing and retrieval latency.
- Runtime resource snapshot command.
- Doctor command for setup readiness checks.

### Index integrity

- Index schema version.
- Engine version.
- Manifest validation on save and load.
- Embedding dimensionality validation.
- Chunk-count validation.
- Source document fingerprints.
- Build metrics.
- Manifest-recorded embedding backend.

### Operational CLI

- `index`
- `inspect`
- `search`
- `ask`
- `version`
- `benchmark`
- `resources`
- `doctor`
- `--json` support for automation.
- llama.cpp server URL support.
- generation options for llama.cpp.
- Local model path metadata support.
- llama-server command generation.
- Embedding backend selection with `--embedding hash|natural`.

### Privacy controls

- Offline default behavior.
- No remote calls unless `--llama-server` is explicitly passed.
- Documentation warning against remote servers for private documents.

### Resource controls

- Max input size during indexing.
- Thermal critical-state rejection.
- Thermal serious-state context reduction.
- Max retrieved chunks per prompt.
- Resident memory snapshot support.
- Optional resident memory ceiling in `ResourceBudget`.
- CLI `--max-resident-mb` option for indexing, retrieval, answering, and benchmarking.

## Remaining hardening work

These are not blockers for a portfolio-quality native RAG engine, but they are required before calling this a commercial App Store-ready product.

### Model backend

- Add MLX Swift, Core ML, or llama.cpp embeddings for larger model-backed retrieval options.
- Add direct llama.cpp C/C++ interoperability if the product should run without a separate server process.
- Add model download/import UX.
- Add model compatibility checks.

### Performance

- Add benchmark command for index throughput, retrieval latency, and answer latency.
- Add memory-resident index format for larger corpora.
- Add approximate nearest-neighbor search for large indexes.
- Add Metal/MLX profiling once real local model execution is integrated.

### macOS app packaging

- Optional future polish: add a richer Preferences window for all CLI configuration fields, not only embedding and hotkey settings.

### Security

- Add encrypted index storage option.
- Add file allowlist/denylist controls.
- Add audit logs for indexed paths.
- Add secure deletion workflow for generated indexes.

## Definition of done for this repo stage

This stage is complete when:

1. `swift test` passes.
2. `scripts/smoke-test.sh` passes.
3. `scripts/package-macos-app.sh` produces `dist/On-Device AI Engine.app`.
4. `scripts/release-check.sh` passes.
5. README, architecture, product, operations, release, and portfolio docs match actual behavior.
6. CLI supports indexing, inspecting, retrieval-only search, answering, JSON output, and version reporting.
7. CLI supports resource snapshots, benchmarking, doctor checks, and configuration files.
8. The documentation clearly separates implemented capabilities from future MLX/Metal/C++ milestones.
