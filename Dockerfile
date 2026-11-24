# =============================================================================
# BentoPDF-Deploy — Dockerfile
#
# Étape 1 (builder) : télécharge BentoPDF, installe les dépendances npm,
#                     compile le frontend Vite, et intègre les assets WASM
#                     préparés localement (dossier wasm/).
#
# Étape 2 (runtime) : nginx:alpine sert le bundle statique en HTTPS.
#                     Les certificats TLS sont montés depuis l'hôte (certs/).
#                     La config NGINX est définie dans nginx/nginx.conf.
#
# Prérequis :
#   Lancer ./scripts/fetch-wasm.sh avant docker compose build
#   pour peupler le dossier wasm/ avec les assets WASM.
#
# Ports :
#   80  — HTTP  (redirige automatiquement vers HTTPS)
#   443 — HTTPS (nécessite cert.pem et key.pem dans certs/)
# =============================================================================

# ===========================================================================
# ÉTAPE 1 — BUILD
# ===========================================================================
FROM node:22-alpine AS builder

# Valeurs injectées depuis docker-compose.yml (section args)
ARG BENTOPDF_VERSION
ARG SIMPLE_MODE=true
ARG VITE_DEFAULT_LANGUAGE
ARG VITE_BRAND_NAME
ARG VITE_BRAND_LOGO
ARG VITE_FOOTER_TEXT
ARG DISABLE_TOOLS
ARG VITE_TESSERACT_AVAILABLE_LANGUAGES=eng,fra

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
    VITE_TESSERACT_AVAILABLE_LANGUAGES=$VITE_TESSERACT_AVAILABLE_LANGUAGES

WORKDIR /build

# Téléchargement de l'archive source BentoPDF depuis GitHub
RUN wget --tries=5 --timeout=30 \
        -O /tmp/bentopdf.tar.gz \
        "https://github.com/alam00000/bentopdf/archive/refs/tags/${BENTOPDF_VERSION}.tar.gz" || \
    { echo "Erreur : impossible de télécharger BentoPDF '${BENTOPDF_VERSION}'." >&2; exit 1; } && \
    tar -xzf /tmp/bentopdf.tar.gz --strip-components=1 -C /build && \
    rm -f /tmp/bentopdf.tar.gz && \
    test -f package.json

# Configuration npm pour les réseaux lents
RUN npm config set fetch-retries 5 && \
    npm config set fetch-retry-mintimeout 60000 && \
    npm config set fetch-retry-maxtimeout 300000 && \
    npm config set fetch-timeout 600000

# Installation des dépendances (respecte le package-lock.json)
RUN npm ci

# Compilation du frontend (build:docker = vite build uniquement)
COPY branding/ public/images/
RUN npm run build:docker

# Fichier de configuration runtime par défaut
RUN printf '{"disabledTools":[],"editorDisabledCategories":[]}\n' > dist/config.json

# ── Injection des assets WASM / OCR ──────────────────────────────────────────
# Les fichiers WASM sont préparés localement par scripts/fetch-wasm.sh
# et copiés ici dans l'image (pas de téléchargement réseau au moment du build).
COPY wasm/ dist/

# ===========================================================================
# ÉTAPE 2 — RUNTIME
# ===========================================================================
FROM nginx:alpine AS runtime-base

ENV HTTPS_PORT=443 \
    NGINX_ENVSUBST_OUTPUT_DIR=/etc/nginx \
    NGINX_ENVSUBST_FILTER=^HTTPS_PORT$

# Configuration NGINX (template — ${HTTPS_PORT} est substitué au démarrage par envsubst)
COPY nginx/nginx.conf /etc/nginx/templates/nginx.conf.template
COPY nginx/security-headers.conf /etc/nginx/security-headers.conf

# HTTP (redirige vers HTTPS) et HTTPS
EXPOSE 80 443
HEALTHCHECK --interval=60s --timeout=5s --retries=3 \
  CMD wget -q --spider --no-check-certificate https://127.0.0.1/ || exit 1
CMD ["nginx", "-g", "daemon off;"]

FROM runtime-base AS runtime
COPY --from=builder /build/dist /usr/share/nginx/html
