# Guide de déploiement

Ce guide couvre l'installation complète de BentoPDF-Deploy, de la préparation des assets jusqu'à la vérification du service.

---

## Prérequis

| Composant | Version minimale | Rôle |
|---|---|---|
| Docker Engine | 24.0+ | Build et exécution du conteneur |
| Docker Compose | v2.0+ (plugin) | Orchestration |
| Node.js + npm | 22.12+ | Préparation des assets WASM |
| RAM | 4 Go minimum (8 Go recommandés) | Compilation Vite + LibreOffice WASM |
| Espace disque | ~4 Go build, ~1 Go runtime | Cache npm + image Docker |

**Accès internet requis pour la préparation et les builds sans cache** :

| Hôte | Usage |
|---|---|
| `github.com`, `raw.githubusercontent.com`, `codeload.github.com` | Sources et lockfile BentoPDF |
| `registry.npmjs.org` | Packages WASM et OCR |
| `cdn.sheetjs.com` | Archive SheetJS référencée par le lockfile upstream |
| Docker Hub | Images de base `node:22-alpine` et `nginx:alpine` |

---

## Étape 1 — Cloner le dépôt

```bash
git clone https://github.com/Miiraak/BentoPDF-Deploy.git
cd BentoPDF-Deploy
```

---

## Étape 2 — Préparer les assets WASM

Le script `fetch-wasm.sh` télécharge tous les binaires WASM nécessaires (LibreOffice, PyMuPDF, Ghostscript, CoherentPDF, Tesseract) et les dépose dans le dossier `wasm/` local. Le Dockerfile les intégrera ensuite dans l'image sans téléchargement réseau.

```bash
./scripts/fetch-wasm.sh
```

Le script lit automatiquement `BENTOPDF_VERSION` et les langues OCR depuis `docker-compose.yml`. LibreOffice, Tesseract et son core utilisent les versions exactes du `package-lock.json` upstream. Les autres packages WASM et modèles OCR utilisent npm `latest` : leur résolution n'est pas reproductible d'une préparation à l'autre.

**Pour inclure des langues OCR supplémentaires**, configurer `VITE_TESSERACT_AVAILABLE_LANGUAGES: "eng,fra,deu"` dans les `args` de Compose, puis lancer :

```bash
./scripts/fetch-wasm.sh
```

Les langues par défaut sont `eng` (anglais) et `fra` (français).  
Liste des codes disponibles : [github.com/naptha/tessdata](https://github.com/naptha/tessdata/tree/gh-pages/4.0.0)

> Cette étape est à relancer uniquement lors d'un changement de `BENTOPDF_VERSION` ou pour ajouter des langues OCR.

---

## Étape 3 — Préparer les certificats TLS

HTTPS est obligatoire pour que BentoPDF fonctionne correctement (le contexte sécurisé est requis pour SharedArrayBuffer/WASM).

```bash
# Copier les certificats au format PEM dans certs/
cp /chemin/vers/cert.pem certs/cert.pem
cp /chemin/vers/key.pem  certs/key.pem

# Appliquer les permissions correctes
chmod 644 certs/cert.pem   # Certificat : lisible par tous
chmod 640 certs/key.pem    # Clé privée : lecture réservée au propriétaire et au groupe
```

> Voir [certificat.md](certificat.md) pour générer des certificats (PKI interne, Let's Encrypt, auto-signé).

---

## Étape 4 — Configurer (optionnel)

Ouvrir `docker-compose.yml` et ajuster les valeurs selon vos besoins :

```yaml
args:
  BENTOPDF_VERSION: "v2.8.12"      # Version BentoPDF à compiler
  SIMPLE_MODE: "true"               # Mode self-hosted (sans page marketing)
  VITE_DEFAULT_LANGUAGE: "fr"      # Langue de l'interface (fr, en, de, es, …)
  VITE_BRAND_NAME: "BentoPDF"      # Nom affiché dans l'interface
  VITE_BRAND_LOGO: ""              # Chemin logo relatif à public/ (optionnel)
  VITE_FOOTER_TEXT: ""             # Texte du pied de page (optionnel)
  DISABLE_TOOLS: ""                # IDs d'outils à masquer (ex: "sign,extract-image")
  VITE_TESSERACT_AVAILABLE_LANGUAGES: "eng,fra"

environment:
  HTTPS_PORT: "443"                # Port HTTPS — doit correspondre au port mappé ci-dessous

ports:
  - "80:80"                        # Port HTTP sur l'hôte
  - "443:443"                      # Port HTTPS sur l'hôte
```

> Voir [customisation.md](customisation.md) pour le détail de toutes les options.

---

## Étape 5 — Builder et démarrer

```bash
docker compose up --build -d
```

| Phase | Durée estimée |
|---|---|
| Première construction | 10–15 minutes |
| Reconstructions suivantes (cache Docker) | 5–10 minutes |

Suivre les logs en temps réel :

```bash
docker compose logs -f bentopdf
```

---

## Vérification

```bash
# État du conteneur
docker compose ps

# Test HTTPS — doit retourner 200 OK
curl -skI https://localhost/

# Test HTTP — doit retourner 301 vers https://
curl -I http://localhost/

# Vérification des headers Cross-Origin (requis pour WASM SharedArrayBuffer)
curl -skI https://localhost/ | grep -i "cross-origin"
```

| Test | Résultat attendu |
|---|---|
| `docker compose ps` | Statut `Up (healthy)` après le contrôle HTTPS |
| HTTPS `curl` | `HTTP/1.1 200 OK` |
| HTTP `curl` | `301 Moved Permanently` → `https://` |
| `Cross-Origin-Embedder-Policy` | `require-corp` |
| `Cross-Origin-Opener-Policy` | `same-origin` |
| `Cross-Origin-Resource-Policy` | `cross-origin` |

---

## Mise à jour

Pour mettre à jour vers une nouvelle version de BentoPDF :

```bash
# 1. Modifier BENTOPDF_VERSION dans docker-compose.yml
#    (choisir un tag upstream publié)

# 2. Mettre à jour les assets WASM pour la nouvelle version
./scripts/fetch-wasm.sh

# 3. Reconstruire et redémarrer le conteneur
docker compose up --build -d
```

---

## Arrêt

```bash
# Arrêter le conteneur (conserve l'image)
docker compose down

# Arrêter et supprimer l'image locale (libère ~1 Go)
docker compose down --rmi local

# Libérer le cache de build Docker (libère plusieurs Go)
docker builder prune -a
```

---

## Dépannage

### Le conteneur ne démarre pas

Consulter les logs pour identifier la cause :

```bash
docker compose logs bentopdf
```

| Symptôme dans les logs | Cause probable | Solution |
|---|---|---|
| `cannot load certificate` | `cert.pem` absent ou chemin incorrect | Vérifier `ls certs/cert.pem` |
| `cannot load private key` | `key.pem` absent ou permissions insuffisantes | `chmod 640 certs/key.pem` |
| `address already in use :80` | Port 80 déjà occupé sur l'hôte | Changer le port dans `docker-compose.yml` |
| `address already in use :443` | Port 443 déjà occupé sur l'hôte | Changer le port dans `docker-compose.yml` |
| `[emerg] SSL_CTX_use_PrivateKey_file` | Clé privée ne correspond pas au certificat | Vérifier la cohérence (voir ci-dessous) |

### Vérifier la cohérence du certificat et de la clé

```bash
# Afficher le sujet et les dates de validité
openssl x509 -in certs/cert.pem -noout -subject -dates

# Les deux commandes doivent retourner le même SHA-256 (RSA ou EC)
openssl x509 -in certs/cert.pem -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256
openssl pkey -in certs/key.pem -pubout -outform DER | openssl dgst -sha256
```

### Échec du build (mémoire insuffisante)

```bash
# Vérifier la mémoire disponible pour Docker
docker system info | grep -i memory

# Nettoyer le cache de build
docker builder prune -a

# Relancer le build
docker compose up --build -d
```

### Échec du build (réseau)

`npm ci` télécharge aussi SheetJS depuis `cdn.sheetjs.com`. Une erreur DNS ou un blocage de ce domaine empêche le build, même si npm et GitHub sont accessibles. Autoriser les hôtes listés dans les prérequis ; ne pas remplacer une dépendance verrouillée par une autre version pour contourner cet échec.

### Accès bloqué (ERR_SSL_PROTOCOL_ERROR ou similaire)

- Vérifier que le certificat est reconnu par votre navigateur (voir [certificat.md](certificat.md))
- Vérifier que les ports 80 et 443 ne sont pas bloqués par un pare-feu
- Vérifier que le nom d'hôte dans le certificat correspond à l'URL utilisée

### La conversion de fichiers Office bloque vers 50%

Les fichiers LibreOffice WASM doivent être servis avec `Content-Encoding: gzip`. Vérifier que les headers sont corrects :

```bash
curl -skI https://localhost/libreoffice-wasm/soffice.wasm.gz | grep -i "content-encoding"
# Résultat attendu : content-encoding: gzip
```
