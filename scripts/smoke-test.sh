#!/usr/bin/env bash
set -euo pipefail

INDEX_PATH=".edgeai/smoke-index.json"
CONFIG_PATH=".edgeai/smoke-config.json"
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "${FIXTURE_DIR}"' EXIT

cat > "${FIXTURE_DIR}/meeting-notes.md" <<'DOC'
# Meeting Notes

The team agreed to keep document processing offline and to cite local sources.
Action items: Ani will validate the release gate. Morgan will test the hotkey workflow.
DOC

cat > "${FIXTURE_DIR}/thermal-policy.md" <<'DOC'
# Thermal Policy

Thermal safeguards reduce retrieved context when the device is under elevated thermal pressure.
The engine also exposes resident-memory checks before indexing or retrieval.
DOC

swift test
swift run edgeai resources
swift run edgeai runtimes
swift run edgeai runtimes --json
swift run edgeai init-config --output "${CONFIG_PATH}" --input "${FIXTURE_DIR}" --search-mode approximate --scoring native-cxx
swift run edgeai show-config --config "${CONFIG_PATH}"
swift run edgeai index --config "${CONFIG_PATH}" --output "${INDEX_PATH}"
swift run edgeai index --input "${FIXTURE_DIR}" --output "${INDEX_PATH}"
swift run edgeai doctor --index "${INDEX_PATH}" --require-index
swift run edgeai doctor --index "${INDEX_PATH}" --require-index --json
swift run edgeai llama-command --model "${FIXTURE_DIR}/meeting-notes.md" --context-size 1024
swift run edgeai model-info --model "${FIXTURE_DIR}/meeting-notes.md" --json
swift run edgeai inspect --index "${INDEX_PATH}"
swift run edgeai search --index "${INDEX_PATH}" --query "thermal safeguards" --top-k 2 --search-mode approximate --scoring native-cxx
swift run edgeai ask --index "${INDEX_PATH}" --question "What are the action items?"
swift run edgeai ask --index "${INDEX_PATH}" --question "What are the action items?" --json
swift run edgeai benchmark --input "${FIXTURE_DIR}" --query "thermal safeguards" --iterations 5 --search-mode approximate --scoring native-cxx

echo "Smoke test passed."
