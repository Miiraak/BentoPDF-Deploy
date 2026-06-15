#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# fetch-wasm.sh
# Permet de préparer les assets WASM/OCR en local pour le build Docker.
# Il lit la version BentoPDF depuis docker-compose.yml puis télécharge les packages npm nécessaires 
# et les dépose dans wasm/ pour être copiés par le Dockerfile.
#
# Utilisation :
#   ./scripts/fetch-wasm.sh
#
# Variables d'environnement optionnelles :
#   OCR_LANGS   Langues Tesseract séparées par des virgules (défaut : eng,fra)
#   ex: OCR_LANGS="eng,fra,spa" ./scripts/fetch-wasm.sh
#
# Prérequis : bash, wget (ou curl), node, npm
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

# Langues OCR
# Lecture depuis le Dockerfile, avec fallback sur la variable d'environnement
_DF_LANGS=$(grep 'VITE_TESSERACT_AVAILABLE_LANGUAGES=' "$ROOT_DIR/Dockerfile" \
    | sed 's/.*=\([^ \\]*\).*/\1/' | head -1 || true)
OCR_LANGS="${OCR_LANGS:-${_DF_LANGS:-eng,fra}}"

echo "═══════════════════════════════════════════════════════"
echo " fetch-wasm — BentoPDF ${BENTOPDF_VERSION}"
echo " Langues OCR : ${OCR_LANGS}"
echo "═══════════════════════════════════════════════════════"

# Téléchargement du package.json BentoPDF pour lire les versions 
echo ""
echo "Lecture des versions de packages depuis BentoPDF ${BENTOPDF_VERSION}..."

_RAW_URL="https://raw.githubusercontent.com/alam00000/bentopdf/refs/tags/${BENTOPDF_VERSION}/package.json"
if command -v wget &>/dev/null; then
    _PKGJSON=$(wget -qO- "$_RAW_URL") || \
        { echo "Impossible de télécharger package.json pour '${BENTOPDF_VERSION}'." >&2; exit 1; }
else
    _PKGJSON=$(curl -sfL "$_RAW_URL") || \
        { echo "Impossible de télécharger package.json pour '${BENTOPDF_VERSION}'." >&2; exit 1; }
fi

# Extraction des versions via node (disponible comme prérequis de npm)
_read_ver() {
    # $1 = clé de dépendance (ex: "@matbee/libreoffice-converter")
    echo "$_PKGJSON" | node -e "
const pkg = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
const raw = (pkg.dependencies || {})['$1'] || (pkg.devDependencies || {})['$1'] || '';
// Supprime les préfixes semver (^, ~, >=, etc.)
console.log(raw.replace(/^[^0-9]*/, ''));
"
}

LIBREOFFICE_VER=$(_read_ver "@matbee/libreoffice-converter")
TESSERACT_VER=$(_read_ver "tesseract.js")

echo "  @matbee/libreoffice-converter : ${LIBREOFFICE_VER}"
echo "  tesseract.js                  : ${TESSERACT_VER}"
echo "  @bentopdf/pymupdf-wasm        : latest"
echo "  @bentopdf/gs-wasm             : latest"
echo "  coherentpdf                   : latest"

# Répertoire de travail temporaire pour l'installation npm
WORKDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$WORKDIR'" EXIT

cat > "$WORKDIR/package.json" << 'EOF'
{"name":"fetch-wasm-temp","private":true,"version":"0.0.0"}
EOF

echo ""
echo "Installation des packages npm dans un répertoire temporaire..."

cd "$WORKDIR"

npm config set fetch-retries 3 2>/dev/null || true
npm config set fetch-retry-mintimeout 30000 2>/dev/null || true
npm config set fetch-timeout 300000 2>/dev/null || true

# Packages avec version fixée par BentoPDF
NPM_PKGS=(
    "@matbee/libreoffice-converter@${LIBREOFFICE_VER}"
    "tesseract.js@${TESSERACT_VER}"
)

# Packages WASM additionnels (non listés dans les deps BentoPDF, version latest)
NPM_PKGS+=(
    "@bentopdf/pymupdf-wasm"
    "@bentopdf/gs-wasm"
    "coherentpdf"
)

# Données OCR Tesseract (une par langue)
IFS=',' read -ra LANG_ARRAY <<< "$OCR_LANGS"
for lang in "${LANG_ARRAY[@]}"; do
    lang="${lang// /}"  # supprimer espaces éventuels
    NPM_PKGS+=("@tesseract.js-data/${lang}")
done

npm install --no-save "${NPM_PKGS[@]}"

# tesseract.js-core → dépendance de tesseract.js (déjà installée)
if [ ! -d "$WORKDIR/node_modules/tesseract.js-core" ]; then
    echo "  tesseract.js-core non trouvé en dépendance transitive, installation séparée..."
    npm install --no-save "tesseract.js-core@${TESSERACT_VER}"
fi

# Destination : wasm/ dans le repo 
DEST="$ROOT_DIR/wasm"

echo ""
echo "Copie des assets vers ${DEST}/..."

# PyMuPDF WASM
echo "  pymupdf..."
mkdir -p "$DEST/wasm/pymupdf"
cp -r "$WORKDIR/node_modules/@bentopdf/pymupdf-wasm/." "$DEST/wasm/pymupdf/"

# Ghostscript WASM
echo "  ghostscript..."
mkdir -p "$DEST/wasm/ghostscript"
cp -r "$WORKDIR/node_modules/@bentopdf/gs-wasm/assets/." "$DEST/wasm/ghostscript/"

# CoherentPDF WASM
echo "  cpdf..."
mkdir -p "$DEST/wasm/cpdf"
cp -r "$WORKDIR/node_modules/coherentpdf/dist/." "$DEST/wasm/cpdf/"

# LibreOffice WASM (avec compression gzip des fichiers lourds)
echo "  libreoffice-wasm..."
mkdir -p "$DEST/libreoffice-wasm"
cp "$WORKDIR/node_modules/@matbee/libreoffice-converter/wasm/soffice.js" \
   "$DEST/libreoffice-wasm/"
cp "$WORKDIR/node_modules/@matbee/libreoffice-converter/wasm/soffice.worker.js" \
   "$DEST/libreoffice-wasm/"
cp "$WORKDIR/node_modules/@matbee/libreoffice-converter/dist/browser.worker.global.js" \
   "$DEST/libreoffice-wasm/"
gzip -9c "$WORKDIR/node_modules/@matbee/libreoffice-converter/wasm/soffice.wasm" \
    > "$DEST/libreoffice-wasm/soffice.wasm.gz"
gzip -9c "$WORKDIR/node_modules/@matbee/libreoffice-converter/wasm/soffice.data" \
    > "$DEST/libreoffice-wasm/soffice.data.gz"

# Tesseract worker + core
echo "  tesseract..."
mkdir -p "$DEST/wasm/tesseract/core" "$DEST/wasm/tesseract/lang-data"
cp "$WORKDIR/node_modules/tesseract.js/dist/worker.min.js" \
   "$DEST/wasm/tesseract/"
cp -r "$WORKDIR/node_modules/tesseract.js-core/." \
   "$DEST/wasm/tesseract/core/"

# Données OCR
echo "  lang-data (${OCR_LANGS})..."
for lang in "${LANG_ARRAY[@]}"; do
    lang="${lang// /}"
    LANG_FILE=$(find "$WORKDIR/node_modules/@tesseract.js-data/${lang}" \
        -name "*.traineddata.gz" 2>/dev/null | head -1 || true)
    if [ -n "$LANG_FILE" ]; then
        cp "$LANG_FILE" "$DEST/wasm/tesseract/lang-data/"
        echo "    ${lang}.traineddata.gz - OK"
    else
        echo "    Données introuvables pour la langue '${lang}'" >&2
    fi
done

echo ""
echo "Assets WASM prêts dans wasm/"
echo "Lancez : docker compose up --build -d"
