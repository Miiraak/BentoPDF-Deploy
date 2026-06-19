# Customisation

Toutes les options de personnalisation se configurent dans `docker-compose.yml` dans la section `args` (variables de build) ou `environment` (variables runtime). 
Un `docker compose up --build -d` est nécessaire après une modification des `args`.

---

## Mode de déploiement (`SIMPLE_MODE`)

| Variable | Défaut | Description |
|---|---|---|
| `SIMPLE_MODE` | `true` | `true` = interface outils uniquement · `false` = build commercial complet avec page marketing |

Le mode `SIMPLE_MODE=true` supprime la page d'accueil marketing et affiche directement l'ensemble des outils PDF. 
**Mode recommandé pour un déploiement interne ou en équipe.**

```yaml
args:
  SIMPLE_MODE: "true" 
```

---

## Branding

| Variable | Défaut | Description |
|---|---|---|
| `VITE_BRAND_NAME` | `BentoPDF` | Nom affiché dans l'interface et l'onglet navigateur |
| `VITE_BRAND_LOGO` | *(vide)* | Chemin du logo (ex : `images/logo.svg`) |
| `VITE_FOOTER_TEXT` | *(vide)* | Texte personnalisé dans le pied de page |
| `VITE_DEFAULT_LANGUAGE` | `fr` | Langue de l'interface au premier chargement |

**Langues disponibles :** `fr`, `en`, `de`, `es`, `it`, `pt`, `nl`, `sv`, `da`, `ru`, `uk`, `be`, `ar`, `id`, `tr`, `vi`, `ko`, `ja`, `zh`, `zh-TW`

Exemple de configuration dans `docker-compose.yml` :

```yaml
args:
  VITE_BRAND_NAME: "MonEntreprise PDF"
  VITE_BRAND_LOGO: "images/logo.svg"
  VITE_FOOTER_TEXT: "Usage interne uniquement — © 2025 MonEntreprise"
  VITE_DEFAULT_LANGUAGE: "fr"
```

### Logo personnalisé

Déposer le fichier image dans le dossier `branding/`
Ajouter une instruction `COPY` dans le Dockerfile pour l'intégrer avant la compilation Vite
```
# Dans le Dockerfile, avant RUN npm run build:docker :
COPY branding/logo.ico /build/public/images/logo.svg
```

Puis référencez le chemin dans docker-compose.yml :
```yaml
args:
  VITE_BRAND_LOGO: "images/logo.ico"
```

---

## Désactiver des outils (`DISABLE_TOOLS`)

| Variable | Défaut | Description |
|---|---|---|
| `DISABLE_TOOLS` | *(vide)* | IDs d'outils à masquer dans l'interface, séparés par virgule |

Cette option masque des outils spécifiques de l'interface sans recompiler BentoPDF.

```yaml
args:
  DISABLE_TOOLS: "sign,extract-image"    # masque les outils Signer et Extraire images
```

Les IDs disponibles correspondent aux noms d'outils définis dans le dépôt BentoPDF. Exemples courants : `compress`, `merge`, `split`, `sign`, `extract-image`, `ocr`, `convert-to-pdf`, `pdf-to-word`.

---

## Version BentoPDF

```yaml
args:
  BENTOPDF_VERSION: "v2.8.5"    # ← changer le tag ici
```

Tags disponibles : [github.com/alam00000/bentopdf/tags](https://github.com/alam00000/bentopdf/tags)

> Après un changement de version, relancer `./scripts/fetch-wasm.sh` avant de rebuilder l'image pour mettre à jour les assets WASM en cohérence avec la nouvelle version.

---

## Ports
[In Work]

---

## Langues OCR (Tesseract)
[In Work]

---

## Configuration runtime (`config.json`)
[In Work]
