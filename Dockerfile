# BentoPDF-Deploy - Dockerfile
# ÉTAPE 1 - BUILD
# -----------------------------------------------------------------------------
FROM node:20-alpine AS builder

# Les valeurs sont injectées depuis le docker-compose.yml
ARG BENTOPDF_VERSION
ARG SIMPLE_MODE=true
ARG VITE_DEFAULT_LANGUAGE
ARG VITE_BRAND_NAME
ARG VITE_BRAND_LOGO
ARG VITE_FOOTER_TEXT
ARG DISABLE_TOOLS

# Variables d'environnement transmises à Vite au moment du build
ENV HUSKY=0 \
    NODE_OPTIONS="--max-old-space-size=3072" \
    SIMPLE_MODE=$SIMPLE_MODE \
    VITE_DEFAULT_LANGUAGE=$VITE_DEFAULT_LANGUAGE \
    VITE_BRAND_NAME=$VITE_BRAND_NAME \
    VITE_BRAND_LOGO=$VITE_BRAND_LOGO \
    VITE_FOOTER_TEXT=$VITE_FOOTER_TEXT \
    DISABLE_TOOLS=$DISABLE_TOOLS \
    VITE_WASM_PYMUPDF_URL=/wasm/pymupdf/ \
    VITE_WASM_GS_URL=/wasm/ghostscript/ \
    VITE_WASM_CPDF_URL=/wasm/cpdf/ \
    VITE_TESSERACT_WORKER_URL=/wasm/tesseract/worker.min.js \
    VITE_TESSERACT_CORE_URL=/wasm/tesseract/core/ \
    VITE_TESSERACT_LANG_URL=/wasm/tesseract/lang-data/ \
    VITE_TESSERACT_AVAILABLE_LANGUAGES=eng,fra

WORKDIR /build

# Téléchargement de l'archive source BentoPDF depuis GitHub
RUN wget --tries=5 --timeout=30 \
        -O /tmp/bentopdf.tar.gz \
        "https://github.com/alam00000/bentopdf/archive/refs/tags/${BENTOPDF_VERSION}.tar.gz" || \
    { echo "Erreur : impossible de télécharger BentoPDF '${BENTOPDF_VERSION}'." >&2; exit 1; } && \
    tar -xzf /tmp/bentopdf.tar.gz --strip-components=1 -C /build && \
    rm -f /tmp/bentopdf.tar.gz && \
    test -f package.json

# Configuration npm (aide si réseau instable)
RUN npm config set fetch-retries 5 && \
    npm config set fetch-retry-mintimeout 60000 && \
    npm config set fetch-retry-maxtimeout 300000 && \
    npm config set fetch-timeout 600000

# Installation des dépendances (respecte le package-lock.json)
RUN npm ci

# Compilation du frontend
RUN npm run build:docker

# Fichier de configuration runtime par défaut
RUN printf '{"disabledTools":[],"editorDisabledCategories":[]}\n' > dist/config.json

# Injection des assets WASM / OCR dans la distribution finale.
COPY wasm/ dist/

# -----------------------------------------------------------------------------
# ÉTAPE 2 - RUNTIME
# -----------------------------------------------------------------------------
FROM nginx:alpine

# Copie du bundle statique compilé
COPY --from=builder /build/dist /usr/share/nginx/html

# Injection de la configuration NGINX dans l'image finale
COPY nginx/nginx.conf /etc/nginx/nginx.conf.template

# Exposition des ports HTTP et HTTPS
EXPOSE 80 443

# Configuration du healthcheck pour vérifier que le serveur est opérationnel
HEALTHCHECK --interval=60s --timeout=5s --retries=3 \
  CMD curl -fsS http://127.0.0.1:80/ >/dev/null || exit 1

# Commande de démarrage : nginx en mode foreground
CMD ["nginx", "-g", "daemon off;"]
