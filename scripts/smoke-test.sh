#!/usr/bin/env bash
set -euo pipefail

INDEX_PATH=".edgeai/smoke-index.json"
CONFIG_PATH=".edgeai/smoke-config.json"

swift test
swift run edgeai resources
swift run edgeai init-config --output "${CONFIG_PATH}" --input sample_docs
swift run edgeai show-config --config "${CONFIG_PATH}"
swift run edgeai index --config "${CONFIG_PATH}" --output "${INDEX_PATH}"
swift run edgeai index --input sample_docs --output "${INDEX_PATH}"
swift run edgeai doctor --index "${INDEX_PATH}" --require-index
swift run edgeai doctor --index "${INDEX_PATH}" --require-index --json
swift run edgeai llama-command --model sample_docs/meeting-notes.md --context-size 1024
swift run edgeai model-info --model sample_docs/meeting-notes.md --json
swift run edgeai inspect --index "${INDEX_PATH}"
swift run edgeai search --index "${INDEX_PATH}" --query "thermal safeguards" --top-k 2
swift run edgeai ask --index "${INDEX_PATH}" --question "What are the action items?"
swift run edgeai ask --index "${INDEX_PATH}" --question "What are the action items?" --json
swift run edgeai benchmark --input sample_docs --query "thermal safeguards" --iterations 5

echo "Smoke test passed."
