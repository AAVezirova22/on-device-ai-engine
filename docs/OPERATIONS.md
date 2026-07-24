# Operations Guide

## Requirements

- macOS 14 or newer.
- Xcode command line tools.
- Swift 6-compatible toolchain.
- Optional: llama.cpp with a local `.gguf` model.

Verify Swift:

```bash
swift --version
```

## Build

```bash
swift build
```

## Test

```bash
swift test
```

## Smoke test

```bash
scripts/smoke-test.sh
```

The smoke test builds the package, checks resource reporting, indexes sample documents, inspects the index, runs retrieval-only search, runs answer commands, verifies JSON output, and runs a small benchmark.

## Release check

```bash
scripts/release-check.sh
```

The release check runs tests, the smoke test, a release build, and sanity checks against the release binary.

## Index documents

```bash
swift run edgeai index \
  --input sample_docs \
  --output .edgeai/index.json
```

Multiple inputs are supported:

```bash
swift run edgeai index \
  --input ~/Documents/Notes \
  --input ~/Documents/PDFs \
  --output .edgeai/work.json
```

Useful options:

- `--embedding hash`: deterministic portable embedding backend.
- `--embedding natural`: Apple NaturalLanguage semantic embedding backend.
- `--target-words 180`: approximate chunk size.
- `--overlap-words 36`: repeated context between chunks.
- `--max-input-mb 50`: max total input text size.
- `--max-resident-mb 2048`: optional process resident-memory ceiling.
- `--json`: emit machine-readable output.

## Configuration files

Create a config:

```bash
swift run edgeai init-config \
  --output .edgeai/config.json \
  --input sample_docs
```

Show the active config:

```bash
swift run edgeai show-config --config .edgeai/config.json
```

Use the config:

```bash
swift run edgeai index --config .edgeai/config.json
swift run edgeai ask --config .edgeai/config.json --question "What are the action items?"
```

Precedence:

1. built-in defaults,
2. config file,
3. explicit CLI flags.

The config stores:

- index path,
- input paths,
- embedding backend,
- chunking settings,
- retrieval settings,
- generation settings,
- resource limits.

## Inspect an index

```bash
swift run edgeai inspect --index .edgeai/index.json
```

JSON:

```bash
swift run edgeai inspect --index .edgeai/index.json --json
```

The manifest includes:

- schema version,
- engine version,
- embedding model name,
- vector dimensionality,
- document count,
- chunk count,
- source document fingerprints,
- build timing,
- chunking configuration.

## Run retrieval only

```bash
swift run edgeai search \
  --index .edgeai/index.json \
  --query "thermal safeguards" \
  --top-k 5
```

Use this when answer quality is weak. If retrieval is poor, the model cannot answer well.

## Embedding backend choice

Default portable backend:

```bash
swift run edgeai index --input sample_docs --embedding hash
```

Semantic Apple local backend:

```bash
swift run edgeai index \
  --input sample_docs \
  --output .edgeai/natural-index.json \
  --embedding natural
```

Use `natural` when the machine supports Apple NaturalLanguage embeddings and you want better semantic matching. Use `hash` when you need deterministic behavior across machines or CI.

The embedding backend is stored in the index manifest. Query commands use the manifest backend automatically.

## Ask questions

```bash
swift run edgeai ask \
  --index .edgeai/index.json \
  --question "What are the action items?"
```

Optional memory ceiling:

```bash
swift run edgeai ask \
  --index .edgeai/index.json \
  --question "What are the action items?" \
  --max-resident-mb 2048
```

Use JSON for automation:

```bash
swift run edgeai ask \
  --index .edgeai/index.json \
  --question "What are the action items?" \
  --json
```

## Check local resources

```bash
swift run edgeai resources
```

JSON:

```bash
swift run edgeai resources --json
```

This reports:

- thermal state,
- physical memory,
- current process resident memory when available.

## Doctor readiness check

```bash
swift run edgeai doctor --index .edgeai/index.json
```

Require an existing index:

```bash
swift run edgeai doctor --index .edgeai/index.json --require-index
```

JSON:

```bash
swift run edgeai doctor --index .edgeai/index.json --json
```

The doctor checks:

- configuration loading,
- thermal and memory state,
- embedding backend availability,
- index schema/dimensions,
- llama.cpp connectivity when a server URL is configured.

## Benchmark

```bash
swift run edgeai benchmark \
  --input sample_docs \
  --query "thermal safeguards" \
  --iterations 25
```

JSON:

```bash
swift run edgeai benchmark \
  --input sample_docs \
  --query "thermal safeguards" \
  --iterations 25 \
  --json
```

The benchmark measures:

- index build time,
- document/chunk throughput,
- retrieval min/average/p95/max latency,
- resource snapshots before and after.

## Use llama.cpp

Start a local server:

```bash
swift run edgeai llama-command --model ./models/mistral-7b-instruct.Q4_K_M.gguf
```

That prints a command equivalent to:

```bash
llama-server \
  -m ./models/mistral-7b-instruct.Q4_K_M.gguf \
  -c 4096 \
  --host 127.0.0.1 \
  --port 8080
```

Inspect configured model metadata:

```bash
swift run edgeai model-info --model ./models/mistral-7b-instruct.Q4_K_M.gguf
```

Ask through that backend:

```bash
swift run edgeai ask \
  --index .edgeai/index.json \
  --question "Summarize the local policy" \
  --llama-server http://127.0.0.1:8080
```

Generation options:

- `--max-tokens 512`
- `--temperature 0.2`

## Run the hotkey helper

```bash
swift run edgeai-hotkey
```

Then:

1. Copy text from any app.
2. Press Control+Option+Command+S.
3. Read the generated summary from the clipboard.

The hotkey helper runs as a menu-bar utility named `EdgeAI`. It exposes:

- visible readiness/status text,
- Summarize Clipboard menu item,
- About menu item,
- Privacy & Permissions menu item,
- Launch at Login menu item,
- Preferences menu item for embedding and hotkey settings,
- Quit menu item,
- global Control+Option+Command+S hotkey.

It reads `.edgeai/config.json` when present and uses the configured embedding backend for clipboard summarization.

Use EdgeAI → Preferences to edit:

- embedding backend,
- hotkey key,
- hotkey modifiers.

Preferences are saved to `.edgeai/config.json`.

Configure the hotkey in `.edgeai/config.json`:

```json
{
  "hotkey": {
    "key": "s",
    "modifiers": ["control", "option", "command"]
  }
}
```

Supported keys are `A-Z` and `0-9`. Supported modifiers are `control`, `option`, `command`, and `shift`.

## Package the macOS app

```bash
scripts/package-macos-app.sh
```

Output:

```text
dist/On-Device AI Engine.app
```

Run:

```bash
open "dist/On-Device AI Engine.app"
```

Current packaging status:

- creates a valid unsigned `.app` bundle,
- includes `Info.plist`,
- runs as an agent/menu-bar app via `LSUIElement`,
- uses the release `edgeai-hotkey` binary.

For distribution outside your own machine, add Developer ID signing and notarization.

Launch at Login uses Apple’s ServiceManagement framework. It generally requires a signed app bundle to register successfully. Unsigned local builds expose the menu item but may show a signing-related error when enabling it.

## Troubleshooting

### `unable to load standard library`

In sandboxed environments, SwiftPM may be blocked from writing compiler caches under the user Library directory. Run the command with the required permissions, or run it in a normal terminal session.

### Weak answers

Run `edgeai search` first. If the relevant source chunks are not retrieved, tune:

- chunk size,
- overlap,
- query wording,
- embedding backend.

### Private documents

Do not use a remote `--llama-server` URL. Keep llama.cpp bound to `127.0.0.1`.

### Large inputs

Increase `--max-input-mb` only when the machine has enough memory. Local inference and large indexes compete for RAM.

Use `--max-resident-mb` to fail fast when the current process exceeds a memory ceiling.
