# Release Guide

This guide describes the verification path before sharing the project publicly or using it as a portfolio artifact.

## Release check

Run:

```bash
scripts/release-check.sh
```

The script verifies:

1. unit tests,
2. end-to-end smoke test,
3. release build,
4. release binary version command,
5. release binary resource command,
6. release binary doctor command,
7. unsigned macOS app bundle packaging.

## Manual release build

```bash
swift build -c release
```

Release binaries:

```text
.build/release/edgeai
.build/release/edgeai-hotkey
```

Verify:

```bash
.build/release/edgeai version
.build/release/edgeai resources
```

## Package unsigned macOS app

```bash
scripts/package-macos-app.sh
```

Output:

```text
dist/On-Device AI Engine.app
```

Run locally:

```bash
open "dist/On-Device AI Engine.app"
```

This app is unsigned. It is suitable as a local portfolio artifact and development build. For public distribution, sign and notarize it.

## Sign and notarize for distribution

Prerequisites:

- Apple Developer Program membership.
- Developer ID Application certificate installed in Keychain.
- App-specific password for notarization.
- Xcode command line tools.

Set environment variables:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID"
export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

Package, sign, and notarize:

```bash
scripts/package-macos-app.sh
scripts/sign-notarize-app.sh "dist/On-Device AI Engine.app"
```

The signing script:

1. validates required environment variables,
2. signs with hardened runtime,
3. verifies code signature,
4. creates a ZIP for notarization,
5. submits through `xcrun notarytool`,
6. staples the notarization ticket,
7. validates Gatekeeper assessment.

## Recommended pre-publication checklist

- Run `scripts/release-check.sh`.
- Read `docs/PORTFOLIO.md` and avoid claiming MLX/Metal/direct C++ inference until implemented.
- Use only sample documents or non-private documents in screenshots.
- Do not commit `.edgeai/*.json` generated from private files.
- Confirm `.gitignore` excludes `.edgeai/` and `.build/`.
- If using llama.cpp, keep the model server bound to `127.0.0.1` for private documents.

## Packaging status

The project releases as SwiftPM command-line binaries and an unsigned `.app` by default. A signing/notarization script is included for users with Apple Developer ID credentials.

For a commercial macOS release, add:

- optional Sparkle-style update distribution,
- richer Preferences controls for all CLI configuration fields.
