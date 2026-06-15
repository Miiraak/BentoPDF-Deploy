# Bento-Deploy

Déploiement auto-hébergé de [BentoPDF](https://github.com/alam00000/bentopdf) avec build local, HTTPS en terminaison TLS, et assets WASM servis 100% offline.

```
HTTP  :80  → NGINX → redirection 301 vers HTTPS
HTTPS :443 → NGINX → TLS + bundle statique BentoPDF (HTML/JS/WASM)
```

L'image Docker compile BentoPDF depuis les sources, embarque tous les assets WASM (LibreOffice, PyMuPDF, Ghostscript, CoherentPDF, Tesseract), et les sert via NGINX sans aucune dépendance réseau au runtime.

---

## Prérequis

| Composant | Version minimale | Rôle |
|---|---|---|
| Docker Engine | 24.0+ | Build et runtime du conteneur |
| Docker Compose | v2.0+ (plugin) | Orchestration |
| Node.js + npm | 18+ | Préparation des assets WASM (hors conteneur) |
| RAM | 4 Go (8 Go recommandés) | Build Vite + LibreOffice WASM |
| Espace disque | ~4 Go build, ~1 Go runtime | Cache npm + image Docker |

Accès internet requis **une seule fois**, avant le premier build :
- `github.com` — sources BentoPDF
- `registry.npmjs.org` — packages WASM/OCR
- `hub.docker.com` — image de base `node:20-alpine` et `nginx:alpine`

---

## Démarrage rapide

```bash
# 1. Cloner le dépôt
git clone https://github.com/Miiraak/BentoPDF-Deploy.git
cd BentoPDF-Deploy

# 2. Télécharger les assets WASM (une seule fois, ou après changement de version)
./scripts/fetch-wasm.sh

# 3. Placer les certificats TLS dans certs/
cp /chemin/vers/cert.pem certs/cert.pem
cp /chemin/vers/key.pem  certs/key.pem
chmod 644 certs/cert.pem
chmod 600 certs/key.pem

# 4. Builder et démarrer
docker compose up --build -d
```

Accès : **`https://<hostname-ou-ip>/`**
> Une fois build, up et sain ; Le serveur qui héberge Bento peut être coupé totalement d'accès internet

Voir [docs/certificat.md](docs/certificat.md) pour générer des certificats (PKI interne ou Let's Encrypt).

---

## Configuration

Toutes les variables sont dans `docker-compose.yml`. Éditez ce fichier directement, puis relancez `docker compose up --build -d`.

### Variables de build (`args`)

| Variable | Défaut | Description |
|---|---|---|
| `BENTOPDF_VERSION` | `v2.8.5` | Tag BentoPDF à compiler - voir [les releases](https://github.com/alam00000/bentopdf/tags) |
| `SIMPLE_MODE` | `true` | `true` = interface outils seuls (sans page marketing) · `false` = build commercial complet |
| `VITE_DEFAULT_LANGUAGE` | `fr` | Langue de l'interface au premier chargement (`fr`, `en`, `de`, `es`, …) |
| `VITE_BRAND_NAME` | `BentoPDF` | Nom affiché dans l'interface et l'onglet navigateur |
| `VITE_BRAND_LOGO` | *(vide)* | Chemin du logo (ex : `branding/logo.svg`) |
| `VITE_FOOTER_TEXT` | *(vide)* | Texte personnalisé dans le pied de page |
| `DISABLE_TOOLS` | *(vide)* | IDs d'outils à masquer, séparés par virgule (ex : `sign,extract-image`) |

### Variables d'environnement runtime

| Variable | Défaut | Description |
|---|---|---|
| `HTTPS_PORT` | `443` | Port HTTPS côté hôte — injecté dans la config NGINX pour les redirections HTTP→HTTPS |

### Ports et volumes

```yaml
ports:
  - "80:80"      # HTTP — redirige automatiquement vers HTTPS
  - "443:443"    # HTTPS (doit correspondre à HTTPS_PORT)

volumes:
  - "./certs:/etc/nginx/certs:ro"   # cert.pem + key.pem montés en lecture seule
```

---

## Vérification

```bash
# État du conteneur
docker compose ps

# Test HTTPS (réponse 200)
curl -skI https://localhost/

# Test HTTP (redirection 301 vers HTTPS)
curl -I http://localhost/

# Vérification des headers de sécurité (COEP/COOP/CORP)
curl -skI https://localhost/ | grep -i "cross-origin"
```

| Test | Résultat attendu |
|---|---|
| `docker compose ps` | `Up (Healthy)` |
| HTTPS `curl` | `HTTP/1.1 200 OK` |
| HTTP `curl` | `301 Moved Permanently` → `https://` |
| Headers COI | `Cross-Origin-Embedder-Policy`, `Cross-Origin-Opener-Policy`, `Cross-Origin-Resource-Policy` |

---

## Structure du projet

```
BentoPDF-Deploy/
├── Dockerfile                  # Build multi-étapes (builder Node + runtime NGINX)
├── docker-compose.yml          # Configuration principale (build args, ports, volumes)
├── nginx/
│   └── nginx.conf              # Config NGINX (template — ${HTTPS_PORT} substitué au démarrage)
├── scripts/
│   └── fetch-wasm.sh           # Prépare les assets WASM/OCR dans wasm/
├── certs/                      # cert.pem + key.pem (gitignorés, montés en volume)
├── branding/                   # Assets de branding personnalisés (gitignorés)
├── wasm/                       # Assets WASM générés par fetch-wasm.sh (gitignorés)
└── docs/
    ├── deployement.md          # Guide de déploiement complet
    ├── certificat.md           # Génération et installation des certificats TLS
    └── customisation.md        # Personnalisation du branding et des options
```

---

## Documentation

| Document | Contenu |
|---|---|
| [docs/deployement.md](docs/deployement.md) | Guide pas-à-pas, mise à jour, arrêt, dépannage |
| [docs/certificat.md](docs/certificat.md) | PKI interne (ADCS), Let's Encrypt, auto-signé, vérification |
| [docs/customisation.md](docs/customisation.md) | Branding, outils, langues OCR, ports, config.json |

---

## Liens

- **BentoPDF upstream :** [github.com/alam00000/bentopdf](https://github.com/alam00000/bentopdf)
- **Issues :** [github.com/Miiraak/Bento-Deploy/issues](https://github.com/Miiraak/Bento-Deploy/issues)

