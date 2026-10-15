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

echo "Fetching croc (${CROC_VERSION:-latest v11 release})..."
go get "github.com/schollz/croc/v11@${CROC_VERSION:-latest}"
go get -tool golang.org/x/mobile/cmd/gobind
go get golang.org/x/mobile/bind
go mod tidy

mkdir -p "$ROOT/Frameworks"
# TARGETS defaults to device + simulator for local work; CI sets TARGETS=ios (device only).
echo "Binding for ${TARGETS:-ios,iossimulator}..."
gomobile bind -target="${TARGETS:-ios,iossimulator}" -o "$ROOT/Frameworks/Croc.xcframework" ./crocmobile

echo "Done: $ROOT/Frameworks/Croc.xcframework"
