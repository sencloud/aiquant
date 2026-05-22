#!/usr/bin/env bash
# Production redeploy helper, executed ON the production host (47.110.227.73:/server).
#
# Pipeline:
#   git pull (fast-forward) → go build → systemctl restart finme-api.prod
#   → quick smoke check on /v1/health
#
# Pre-conditions:
#   - /server is a git checkout of this repo's backend subtree (or symlinks)
#   - Go toolchain (>= 1.22) on PATH
#   - systemd unit `finme-api.prod` installed (see deploy/systemd/finme-api.prod.service)
#
# Usage on server:
#   cd /server
#   bash scripts/deploy_prod.sh

set -euo pipefail

ROOT_DIR="${ROOT_DIR:-/server}"
UNIT_NAME="${UNIT_NAME:-finme-api.prod}"
BIN_OUT="${BIN_OUT:-bin/finme-server}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8080/v1/health}"

log() { printf '\033[1;36m[deploy]\033[0m %s\n' "$*"; }

cd "$ROOT_DIR"

log "git pull (fast-forward) ..."
git fetch --all --prune
git pull --ff-only

log "go build ..."
mkdir -p bin
CGO_ENABLED=0 go build -ldflags "-s -w -X main.Version=$(git rev-parse --short HEAD)" \
  -o "$BIN_OUT" ./cmd/finme-server

log "restart systemd unit ${UNIT_NAME} ..."
systemctl daemon-reload
systemctl restart "$UNIT_NAME"

log "post-restart status:"
systemctl --no-pager --full status "$UNIT_NAME" | head -n 12 || true

log "wait 3s for warmup ..."
sleep 3

if command -v curl >/dev/null 2>&1; then
  log "health check: $HEALTH_URL"
  curl -fsS --max-time 5 "$HEALTH_URL" || {
    log "health check FAILED — check logs: journalctl -u $UNIT_NAME -n 100 --no-pager"
    exit 1
  }
  echo
fi

log "verifying backtest_etf_rotation tool is registered ..."
# 新加的工具应该出现在 chat /tools 调试日志或 /v1/ai/tools 端点（视后端实现）。
# 这里只做一个被动校验：抓最近 50 行日志看是否启动 OK。
if [ -f /server/logs/api.log ]; then
  tail -n 50 /server/logs/api.log | grep -E "listen|started|backtest_etf_rotation" || true
fi

log "done. Version: $(git rev-parse --short HEAD)"
