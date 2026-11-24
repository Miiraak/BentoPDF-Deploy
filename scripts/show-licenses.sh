#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# show-licenses.sh
# Affiche les liens sources (conformité AGPL-3.0) pour BentoPDF et ses
# dépendances WASM, tels qu'ils seraient installés par fetch-wasm.sh a l'instant T.
#
# Utilisation :
#   ./scripts/show-licenses.sh
#
# Prérequis : bash, wget (ou curl), node, git
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Lecture de la version BentoPDF 
BENTOPDF_VERSION=$(grep 'BENTOPDF_VERSION' "$ROOT_DIR/docker-compose.yml" \
    | sed 's/.*"\(.*\)".*/\1/' | head -1)

if [ -z "$BENTOPDF_VERSION" ]; then
    echo "Impossible de lire BENTOPDF_VERSION dans docker-compose.yml." >&2
    exit 1
fi

# Commit actuel du repo BentoPDF-Deploy
DEPLOY_COMMIT=$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")
DEPLOY_REMOTE=$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null \
    | sed 's/\.git$//' || echo "https://github.com/Miiraak/BentoPDF-Deploy")

# Téléchargement du lockfile BentoPDF pour lire les versions exactes
_RAW_URL="https://raw.githubusercontent.com/alam00000/bentopdf/refs/tags/${BENTOPDF_VERSION}/package-lock.json"
if command -v wget &>/dev/null; then
    _PKGJSON=$(wget -qO- "$_RAW_URL") || \
        { echo "Impossible de télécharger package-lock.json pour '${BENTOPDF_VERSION}'." >&2; exit 1; }
else
    _PKGJSON=$(curl -sfL "$_RAW_URL") || \
        { echo "Impossible de télécharger package-lock.json pour '${BENTOPDF_VERSION}'." >&2; exit 1; }
fi

# Résolution des versions via npm registry (sans installation)
_read_pkg_ver() {
    echo "$_PKGJSON" | node -e "
const pkg = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
const version = pkg.packages?.['node_modules/' + process.argv[1]]?.version;
if (!version) throw new Error('Version absente du lockfile : ' + process.argv[1]);
console.log(version);
" "$1"
}

_resolve_npm_latest() {
    # Interroge le registry npm pour obtenir la version latest réelle
    local pkg="$1"
    local encoded="${pkg//@/%40}"
    encoded="${encoded//\//%2F}"
    local url="https://registry.npmjs.org/${encoded}/latest"
    if command -v wget &>/dev/null; then
        wget -qO- "$url" 2>/dev/null | node -e \
            "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); if (!d.version) throw new Error('Version npm absente'); console.log(d.version);"
    else
        curl -sfL "$url" 2>/dev/null | node -e \
            "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); if (!d.version) throw new Error('Version npm absente'); console.log(d.version);"
    fi
}

LIBREOFFICE_VER=$(_read_pkg_ver "@matbee/libreoffice-converter")
TESSERACT_VER=$(_read_pkg_ver "tesseract.js")
TESSERACT_CORE_VER=$(_read_pkg_ver "tesseract.js-core")
PYMUPDF_VER=$(_resolve_npm_latest "@bentopdf/pymupdf-wasm")
GS_VER=$(_resolve_npm_latest "@bentopdf/gs-wasm")
CPDF_VER=$(_resolve_npm_latest "coherentpdf")

# Langues OCR
_COMPOSE_LANGS=$(grep 'VITE_TESSERACT_AVAILABLE_LANGUAGES:' "$ROOT_DIR/docker-compose.yml" \
    | sed 's/.*"\([^"]*\)".*/\1/' | head -1)
OCR_LANGS="${OCR_LANGS:-${_COMPOSE_LANGS}}"
IFS=',' read -ra LANG_ARRAY <<< "$OCR_LANGS"

# Affichage 
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║        Conformité AGPL-3.0 — Sources & Dépendances              ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "┌─ BentoPDF (source principale) ───────────────────────────────────"
echo "│  Licence  : AGPL-3.0-only"
echo "│  Version  : ${BENTOPDF_VERSION}"
echo "│  Source   : https://github.com/alam00000/bentopdf/releases/tag/${BENTOPDF_VERSION}"
echo "│  Code     : https://github.com/alam00000/bentopdf/tree/${BENTOPDF_VERSION}"
echo "│"
echo "├─ BentoPDF-Deploy (configuration de déploiement) ─────────────────"
echo "│  Repo     : ${DEPLOY_REMOTE}"
echo "│  Commit   : ${DEPLOY_COMMIT}"
echo "│  Source   : ${DEPLOY_REMOTE}/tree/${DEPLOY_COMMIT}"
echo "│"
echo "├─ Dépendances WASM (npm) ──────────────────────────────────────────"
echo "│"
echo "│  @matbee/libreoffice-converter@${LIBREOFFICE_VER}"
echo "│    https://www.npmjs.com/package/@matbee/libreoffice-converter/v/${LIBREOFFICE_VER}"
echo "│"
echo "│  tesseract.js@${TESSERACT_VER}"
echo "│    https://www.npmjs.com/package/tesseract.js/v/${TESSERACT_VER}"
echo "│"
echo "│  tesseract.js-core@${TESSERACT_CORE_VER}  (dépendance transitive)"
echo "│    https://www.npmjs.com/package/tesseract.js-core/v/${TESSERACT_CORE_VER}"
echo "│"
echo "│  @bentopdf/pymupdf-wasm@${PYMUPDF_VER}"
echo "│    https://www.npmjs.com/package/@bentopdf/pymupdf-wasm/v/${PYMUPDF_VER}"
echo "│"
echo "│  @bentopdf/gs-wasm@${GS_VER}"
echo "│    https://www.npmjs.com/package/@bentopdf/gs-wasm/v/${GS_VER}"
echo "│"
echo "│  coherentpdf@${CPDF_VER}"
echo "│    https://www.npmjs.com/package/coherentpdf/v/${CPDF_VER}"
echo "│"
echo "├─ Données OCR Tesseract (langues : ${OCR_LANGS}) ──────────────────"

for lang in "${LANG_ARRAY[@]}"; do
    lang="${lang// /}"
    LANG_VER=$(_resolve_npm_latest "@tesseract.js-data/${lang}")
    echo "│"
    echo "│  @tesseract.js-data/${lang}@${LANG_VER}"
    echo "│    https://www.npmjs.com/package/@tesseract.js-data/${lang}/v/${LANG_VER}"
done

echo "│"
echo "└───────────────────────────────────────────────────────────────────"
echo ""
echo " → Copiez ces liens sur votre page intranet de conformité AGPL."
echo ""
