#!/usr/bin/env bash
set -euo pipefail

swift test
scripts/smoke-test.sh
swift build --product EdgeAIIOS
swift build -c release
.build/release/edgeai version
.build/release/edgeai resources
.build/release/edgeai doctor --config .edgeai/smoke-config.json --index .edgeai/smoke-index.json --require-index
scripts/package-macos-app.sh
test -x scripts/sign-notarize-app.sh

echo "Release check passed."
