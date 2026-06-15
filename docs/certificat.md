# Certificats TLS

BentoPDF requiert impérativement HTTPS pour fonctionner hors local. 
Le contexte sécurisé est nécessaire pour l'utilisation de `SharedArrayBuffer` par les modules WASM (LibreOffice, Tesseract, etc.).

Les fichiers `cert.pem` (certificat) et `key.pem` (clé privée) doivent être placés dans le dossier `certs/` avant de démarrer le conteneur. 
Ce dossier est monté en lecture seule dans le conteneur NGINX.

```bash
# Permissions recommandées
chmod 644 certs/cert.pem   # Certificat : lisible par tous (pas sensible)
chmod 600 certs/key.pem    # Clé privée : accès restreint au propriétaire
```

---

## Option A : PKI interne / ADCS (réseau d'entreprise)
[In Work]

---

## Option B : Let's Encrypt (domaine public)
[In Work]

---

## Option C : Certificat auto-signé (test / développement)

**À utiliser uniquement pour les tests locaux.** Les navigateurs afficheront un avertissement de sécurité.
[In Work]

---

## Vérification
[In Work]
