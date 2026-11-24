#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf -- "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/repo/scripts" "$WORKDIR/bin"
cp "$ROOT_DIR/scripts/fetch-wasm.sh" "$WORKDIR/repo/scripts/"
cp "$ROOT_DIR/docker-compose.yml" "$WORKDIR/repo/"

cat > "$WORKDIR/bin/wget" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"packages":{"node_modules/@matbee/libreoffice-converter":{"version":"2.5.0"},"node_modules/tesseract.js":{"version":"7.0.0"},"node_modules/tesseract.js-core":{"version":"6.1.2"}}}
JSON
EOF
cat > "$WORKDIR/bin/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" != *"tesseract.js-core@6.1.2"* ]]; then
    echo "Incorrect core version or unexpected npm command" >&2
    exit 1
fi
mkdir -p node_modules/{@bentopdf/pymupdf-wasm,@bentopdf/gs-wasm/assets,coherentpdf/dist}
mkdir -p node_modules/@matbee/libreoffice-converter/{wasm,dist}
mkdir -p node_modules/{tesseract.js/dist,tesseract.js-core}
touch node_modules/@matbee/libreoffice-converter/wasm/{soffice.js,soffice.worker.js,soffice.wasm,soffice.data}
touch node_modules/@matbee/libreoffice-converter/dist/browser.worker.global.js
touch node_modules/tesseract.js/dist/worker.min.js
EOF
chmod +x "$WORKDIR/bin/"{wget,npm}

if PATH="$WORKDIR/bin:$PATH" OCR_LANGS=eng \
    bash "$WORKDIR/repo/scripts/fetch-wasm.sh" > "$WORKDIR/output" 2>&1; then
    echo "Missing OCR model must fail the preparation" >&2
    exit 1
fi
grep -Fq "Données introuvables pour la langue 'eng'" "$WORKDIR/output"
if grep -Fq "Assets WASM prêts" "$WORKDIR/output"; then
    echo "Preparation reported success despite missing OCR data" >&2
    exit 1
fi

if PATH="$WORKDIR/bin:$PATH" OCR_LANGS='eng,../fra' \
    bash "$WORKDIR/repo/scripts/fetch-wasm.sh" > "$WORKDIR/output" 2>&1; then
    echo "Invalid OCR language must fail before npm installation" >&2
    exit 1
fi
grep -Fq "OCR_LANGS doit contenir des codes" "$WORKDIR/output"
echo "Exact Tesseract core version and explicit OCR failures: OK"
