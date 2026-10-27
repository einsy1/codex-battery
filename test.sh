#!/bin/zsh
set -euo pipefail
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 "$ROOT/Sources/Quota.swift" "$ROOT/Tests/QuotaTests.swift" -o "$TEST_DIR/quota-tests"
"$TEST_DIR/quota-tests"

xcrun swiftc -swift-version 5 "$ROOT/Sources/StatusIcon.swift" "$ROOT/Tests/IconTests.swift" -o "$TEST_DIR/icon-tests" -framework AppKit
"$TEST_DIR/icon-tests" "$TEST_DIR/icon-renders"
