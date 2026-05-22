#!/usr/bin/env bash
set -euo pipefail
cd "$HOME"
mkdir -p .local
cd .local
if [ -x go/bin/go ]; then
  echo "Go already installed:"
  ./go/bin/go version
  exit 0
fi
URL='https://go.dev/dl/go1.22.5.linux-amd64.tar.gz'
echo "download $URL"
curl -fsSL --connect-timeout 15 -o go.tgz "$URL"
echo "extract"
tar xzf go.tgz
rm go.tgz
./go/bin/go version
echo "OK -> $HOME/.local/go/bin/go"
