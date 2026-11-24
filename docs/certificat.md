# Certificats TLS

BentoPDF requiert impérativement HTTPS pour fonctionner. Le contexte sécurisé est nécessaire pour l'utilisation de `SharedArrayBuffer` par les modules WASM (LibreOffice, Tesseract, etc.).

Les fichiers `cert.pem` (certificat) et `key.pem` (clé privée) doivent être placés dans le dossier `certs/` avant de démarrer le conteneur. Ce dossier est monté en lecture seule dans le conteneur NGINX.

```bash
# Permissions recommandées
chmod 644 certs/cert.pem   # Certificat : lisible par tous (pas sensible)
chmod 640 certs/key.pem    # Clé privée : accès restreint au propriétaire et au groupe
```

---

## Option A — PKI interne / ADCS (réseau d'entreprise)

Utilisez cette option si votre organisation dispose d'une autorité de certification (AC) interne, par exemple Microsoft ADCS.

### 1. Créer la requête de certificat (Windows)

```powershell
$req = @'
[Version]
Signature="$Windows NT$"

[NewRequest]
Subject = "CN=bentopdf.exemple.local"
KeySpec = 1
KeyLength = 2048
Exportable = TRUE
MachineKeySet = FALSE
RequestType = PKCS10

[Extensions]
2.5.29.17 = "{text}"
_continue_ = "dns=bentopdf.exemple.local&"
_continue_ = "ipaddress=192.168.1.10&"
'@

$req | Out-File -Encoding ASCII request.inf
certreq -new request.inf request.csr
```

### 2. Soumettre à l'AC

```powershell
certreq -submit -attrib "CertificateTemplate:WebServer" request.csr cert.cer
```

### 3. Exporter la clé privée

`certmgr.msc` → Personnel → Certificats → clic droit sur le certificat → **Toutes les tâches** → **Exporter** → format **PKCS #12 (.pfx)** avec la clé privée incluse.

### 4. Convertir en PEM (Linux)

```bash
# Extraire le certificat serveur
openssl pkcs12 -in certificat.pfx -clcerts -nokeys -out certs/cert.pem

# Ajouter les certificats intermédiaires PEM fournis par votre AC, si nécessaire
cat intermediaires.pem >> certs/cert.pem

# Extraire la clé privée (sans mot de passe dans le fichier de sortie)
openssl pkcs12 -in certificat.pfx -nocerts -nodes -out certs/key.pem

# Appliquer les permissions
chmod 644 certs/cert.pem
chmod 640 certs/key.pem
```

### 5. Faire confiance à l'AC racine

Pour que les navigateurs valident le certificat sans avertissement :

- **Windows (Chrome, Edge, IE) :** `certmgr.msc` → *Autorités de certification racines de confiance* → Importer l'AC racine (.cer)
- **Firefox :** Paramètres → Vie privée et sécurité → Afficher les certificats → Autorités → Importer
- **Linux (curl, système) :** Copier le certificat racine dans `/usr/local/share/ca-certificates/` et exécuter `update-ca-certificates`

---

## Option B — Let's Encrypt (domaine public)

Utilisez cette option si le serveur est accessible depuis internet avec un nom de domaine public.

### Prérequis

- Nom de domaine avec un enregistrement DNS A pointant vers votre serveur
- Port 80 accessible depuis internet (challenge HTTP-01) ou accès à votre DNS (challenge DNS-01)

### 1. Installer Certbot

```bash
# Debian / Ubuntu
apt update && apt install -y certbot

# Alpine Linux
apk add certbot
```

### 2. Obtenir le certificat

**Méthode HTTP-01** (port 80 doit être libre) :

```bash
docker compose down
certbot certonly --standalone -d bentopdf.exemple.com
```

**Méthode DNS-01** (port 80 non requis) :

```bash
certbot certonly --manual --preferred-challenges dns -d bentopdf.exemple.com
# Suivre les instructions pour créer l'enregistrement DNS TXT demandé
```

### 3. Copier les certificats

```bash
cp /etc/letsencrypt/live/bentopdf.exemple.com/fullchain.pem certs/cert.pem
cp /etc/letsencrypt/live/bentopdf.exemple.com/privkey.pem   certs/key.pem
chmod 644 certs/cert.pem
chmod 640 certs/key.pem
docker compose up -d
```

> Utiliser `fullchain.pem` (et non `cert.pem`) pour que les navigateurs valident toute la chaîne de certification.

### 4. Renouvellement automatique (cron)

Let's Encrypt émet des certificats valables 90 jours. Ajouter une tâche cron pour les renouveler automatiquement :

```bash
crontab -e
```

```cron
# Renouvellement Let's Encrypt — lundi et jeudi à 3h00
0 3 * * 1,4 certbot renew --quiet --pre-hook "docker compose -f /chemin/bentopdf-deploy/docker-compose.yml stop bentopdf" --deploy-hook "cp /etc/letsencrypt/live/bentopdf.exemple.com/fullchain.pem /chemin/bentopdf-deploy/certs/cert.pem && cp /etc/letsencrypt/live/bentopdf.exemple.com/privkey.pem /chemin/bentopdf-deploy/certs/key.pem && chmod 640 /chemin/bentopdf-deploy/certs/key.pem" --post-hook "docker compose -f /chemin/bentopdf-deploy/docker-compose.yml start bentopdf"
```

Adapter les chemins et installer cette ligne dans la crontab root. Les hooks libèrent le port 80 pour le challenge standalone et relancent le service après la tentative. La méthode DNS manuelle exige une intervention à chaque renouvellement ; elle ne bénéficie pas de cette automatisation.

---

## Option C — Certificat auto-signé (test / développement)

**⚠️ À utiliser uniquement pour les tests locaux.** Les navigateurs afficheront un avertissement de sécurité.

```bash
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout certs/key.pem \
  -out    certs/cert.pem \
  -subj   "/CN=localhost" \
  -addext "subjectAltName=IP:127.0.0.1,DNS:localhost"

chmod 644 certs/cert.pem
chmod 640 certs/key.pem
```

Pour ignorer la vérification uniquement pendant un test `curl` :

```bash
curl -skI https://localhost/   # -k ignore les erreurs de certificat auto-signé
```

---

## Vérification

```bash
# Afficher le sujet, l'émetteur et les dates de validité
openssl x509 -in certs/cert.pem -noout -text | grep -E "Subject:|Issuer:|Not Before|Not After"

# Vérifier que les clés publiques correspondent (SHA-256 identiques, RSA ou EC)
openssl x509 -in certs/cert.pem -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256
openssl pkey -in certs/key.pem -pubout -outform DER | openssl dgst -sha256

# Vérifier le header HSTS une fois le conteneur démarré
curl -skI https://localhost/ | grep -i "strict-transport"
```

