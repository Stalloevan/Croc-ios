#!/usr/bin/env bash
# Builds Frameworks/Croc.xcframework from the Go wrapper in go/crocmobile.
# Requires: macOS, Xcode (with command line tools), Go, and network access.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/go"

if ! command -v gomobile >/dev/null 2>&1; then
  echo "Installing gomobile..."
  go install golang.org/x/mobile/cmd/gomobile@latest
  export PATH="$PATH:$(go env GOPATH)/bin"
fi

echo "Initialising gomobile..."
gomobile init

echo "Fetching croc (latest v11 release)..."
go get github.com/schollz/croc/v11@latest
go mod tidy

mkdir -p "$ROOT/Frameworks"
echo "Binding for iOS device and simulator..."
gomobile bind -target=ios,iossimulator -o "$ROOT/Frameworks/Croc.xcframework" ./crocmobile

echo "Done: $ROOT/Frameworks/Croc.xcframework"
