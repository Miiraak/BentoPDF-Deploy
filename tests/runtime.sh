#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?Usage: bash tests/runtime.sh IMAGE}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf -- "$WORKDIR"' EXIT
chmod 755 "$WORKDIR"
mkdir -p "$WORKDIR/wasm/tesseract" "$WORKDIR/libreoffice-wasm"
printf '<!doctype html><title>NGINX fixture</title>\n' > "$WORKDIR/index.html"
printf '{"disabledTools":[],"editorDisabledCategories":[]}\n' > "$WORKDIR/config.json"
printf '/* worker fixture */\n' > "$WORKDIR/wasm/tesseract/worker.min.js"
printf 'WASM fixture\n' | gzip > "$WORKDIR/libreoffice-wasm/soffice.wasm.gz"
printf 'Data fixture\n' | gzip > "$WORKDIR/libreoffice-wasm/soffice.data.gz"
bash "$ROOT_DIR/tests/smoke.sh" "$IMAGE" "$WORKDIR"
