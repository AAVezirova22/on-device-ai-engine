#!/usr/bin/env bash
set -euo pipefail

swift test
scripts/smoke-test.sh
swift build -c release
.build/release/edgeai version
.build/release/edgeai resources
.build/release/edgeai doctor --index .edgeai/smoke-index.json --require-index
scripts/package-macos-app.sh
test -x scripts/sign-notarize-app.sh

echo "Release check passed."
