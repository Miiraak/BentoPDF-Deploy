# Customisation

Toutes les options de personnalisation se configurent dans `docker-compose.yml` sous la section `args` (variables de build) ou `environment` (variables runtime). Un `docker compose up --build -d` est nécessaire après toute modification des `args`.

---

## Mode de déploiement (`SIMPLE_MODE`)

| Variable | Défaut | Description |
|---|---|---|
| `SIMPLE_MODE` | `true` | `true` = interface outils uniquement · `false` = build commercial complet avec page marketing |

Le mode `SIMPLE_MODE=true` supprime la page d'accueil marketing (hero, FAQ, témoignages, footer promotionnel) et expose directement l'ensemble des outils PDF. **C'est le mode recommandé pour tout déploiement interne ou en équipe.**

```yaml
args:
  SIMPLE_MODE: "true"    # recommandé pour un usage interne ou en équipe
```

---

## Branding

| Variable | Défaut | Description |
|---|---|---|
| `VITE_BRAND_NAME` | `BentoPDF` | Nom affiché dans l'interface et l'onglet navigateur |
| `VITE_BRAND_LOGO` | *(vide)* | Chemin du logo relatif à `public/` (ex : `images/logo.svg`) |
| `VITE_FOOTER_TEXT` | *(vide)* | Texte personnalisé dans le pied de page |
| `VITE_DEFAULT_LANGUAGE` | `fr` | Langue de l'interface au premier chargement |

**Langues disponibles :** `fr`, `en`, `de`, `es`, `it`, `pt`, `nl`, `sv`, `da`, `ru`, `uk`, `be`, `ar`, `id`, `tr`, `vi`, `ko`, `ja`, `zh`, `zh-TW`

Exemple de configuration dans `docker-compose.yml` :

```yaml
args:
  VITE_BRAND_NAME: "MonEntreprise PDF"
  VITE_BRAND_LOGO: "images/logo.ico"
  VITE_FOOTER_TEXT: "Usage interne uniquement — © 2026 MonEntreprise"
  VITE_DEFAULT_LANGUAGE: "fr"
```

### Logo personnalisé

Déposer `logo.ico` dans `branding/` (gitignoré). Le Dockerfile copie automatiquement ce dossier vers `public/images/` avant la compilation Vite. Référencer ensuite le chemin dans `docker-compose.yml` :

```yaml
args:
  VITE_BRAND_LOGO: "images/logo.ico"
```

---

## Désactiver des outils (`DISABLE_TOOLS`)

| Variable | Défaut | Description |
|---|---|---|
| `DISABLE_TOOLS` | *(vide)* | IDs d'outils à masquer dans l'interface, séparés par virgule |

Cette variable de build masque des outils spécifiques de l'interface et nécessite une reconstruction. Pour une modification sans build, utiliser `config.json` ci-dessous.

```yaml
args:
  DISABLE_TOOLS: "sign,extract-image"    # masque les outils Signer et Extraire images
```

Les IDs disponibles correspondent aux noms d'outils définis dans le dépôt BentoPDF. Exemples courants : `compress`, `merge`, `split`, `sign`, `extract-image`, `ocr`, `convert-to-pdf`, `pdf-to-word`.

---

## Version BentoPDF

```yaml
args:
  BENTOPDF_VERSION: "v2.8.12"    # ← changer le tag ici
```

Tags disponibles : [github.com/alam00000/bentopdf/tags](https://github.com/alam00000/bentopdf/tags)

> ⚠️ Après un changement de version, relancer `./scripts/fetch-wasm.sh` avant de rebuilder l'image pour mettre à jour les assets WASM en cohérence avec la nouvelle version.

---

## Ports

```yaml
environment:
  HTTPS_PORT: "443"    # ← injecté dans la config NGINX pour les redirections HTTP→HTTPS

ports:
  - "80:80"            # ← port HTTP sur l'hôte (redirige vers HTTPS)
  - "443:443"          # ← port HTTPS sur l'hôte (doit correspondre à HTTPS_PORT)
```

Pour utiliser des ports non standard (ex : derrière un reverse proxy) :

```yaml
environment:
  HTTPS_PORT: "8443"

ports:
  - "8080:80"
  - "8443:443"
```

> `HTTPS_PORT` est substitué dans la configuration NGINX au démarrage du conteneur via `envsubst`. La valeur doit toujours correspondre au port hôte HTTPS mappé.

---

## Langues OCR (Tesseract)

Par défaut, les langues `eng` (anglais) et `fra` (français) sont embarquées dans l'image.

Pour ajouter d'autres langues, modifier l'argument de build dans Compose ; le script lit la même valeur :

```yaml
args:
  VITE_TESSERACT_AVAILABLE_LANGUAGES: "eng,fra,deu"
```

```bash
./scripts/fetch-wasm.sh
docker compose up --build -d
```

`OCR_LANGS` permet une surcharge ponctuelle du téléchargement, mais ne change pas l'interface : la valeur dans Compose doit rester cohérente. Ne pas mettre d'espaces entre les codes.

Les codes de langues correspondent aux noms de modèles Tesseract.  
Exemples : `deu` (allemand), `spa` (espagnol), `ita` (italien), `por` (portugais), `nld` (néerlandais), `rus` (russe), `jpn` (japonais), `chi_sim` (chinois simplifié).

Liste complète : [github.com/naptha/tessdata/tree/gh-pages/4.0.0](https://github.com/naptha/tessdata/tree/gh-pages/4.0.0)

---

## Configuration runtime (`config.json`)

L'image embarque un fichier `/config.json` servi par NGINX avec les options de configuration runtime de BentoPDF :

```json
{"disabledTools":[],"editorDisabledCategories":[]}
```

Ce fichier est généré au moment du build Docker avec les valeurs par défaut. Il permet de désactiver des outils ou catégories sans avoir à reconstruire l'image.

Créer un fichier local `config.json`, puis ajouter ce montage au service Compose et recréer le conteneur :

```yaml
volumes:
  - "./certs:/etc/nginx/certs:ro"
  - "./config.json:/usr/share/nginx/html/config.json:ro"
```

> NGINX sert `/config.json` avec `Cache-Control: no-store` pour que les changements soient toujours pris en compte immédiatement.

