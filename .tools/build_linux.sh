#!/usr/bin/env bash
# Cross-compile finme-server (linux/amd64) inside WSL Ubuntu.
# Output -> /mnt/d/GitHub/aiquant/.tools/_build/finme-server
#
# Usage (PowerShell):
#   wsl -d Ubuntu -e bash /mnt/d/GitHub/aiquant/.tools/build_linux.sh

set -euo pipefail
REPO_ROOT="/mnt/d/GitHub/aiquant"
BACKEND_DIR="$REPO_ROOT/backend"
OUT_DIR="$REPO_ROOT/.tools/_build"
OUT_BIN="$OUT_DIR/finme-server"

export PATH="$HOME/.local/go/bin:$PATH"
export GOOS=linux GOARCH=amd64 CGO_ENABLED=0
export GOCACHE="$HOME/.cache/go-build-linux"
export GOMODCACHE="$HOME/.cache/go-mod"

mkdir -p "$OUT_DIR" "$GOCACHE" "$GOMODCACHE"

cd "$BACKEND_DIR"
VERSION="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo dev)"
echo "==> building finme-server (linux/amd64, ${VERSION})"
go build -trimpath -ldflags "-s -w -X main.Version=${VERSION}" \
  -o "$OUT_BIN" ./cmd/finme-server
ls -la "$OUT_BIN"
file "$OUT_BIN" 2>/dev/null || true
sha256sum "$OUT_BIN"
echo "OK: $OUT_BIN"
