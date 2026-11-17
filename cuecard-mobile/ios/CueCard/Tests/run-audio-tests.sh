#!/bin/bash
set -euo pipefail
test_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/cuecard-audio-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun --sdk macosx swiftc \
  "$test_dir/../CueCard/Services/AudioTarget.swift" \
  "$test_dir/AudioTargetTests.swift" \
  -o "$build_dir/audio-tests"
"$build_dir/audio-tests"
