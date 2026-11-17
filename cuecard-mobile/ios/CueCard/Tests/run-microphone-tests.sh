#!/bin/bash
set -euo pipefail
# Pass the UDID of a booted iOS simulator. No camera or microphone is opened.
simulator="${1:?Pass a booted iOS simulator UDID}"
test_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/cuecard-microphone-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator swiftc -parse-as-library \
  -sdk "$sdk" -target "$(uname -m)-apple-ios17.0-simulator" \
  "$test_dir/../CueCard/Services/AudioTarget.swift" \
  "$test_dir/../CueCard/Services/VoiceFollower.swift" \
  "$test_dir/MicrophoneTests.swift" \
  -o "$build_dir/microphone-tests"
xcrun simctl spawn "$simulator" "$build_dir/microphone-tests"
