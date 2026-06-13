#!/bin/sh
# 02-build-repo.sh — Signe le dépôt pkg et le publie.
#
# Génère (une seule fois) une paire de clés RSA, signe le catalogue du dépôt
# produit par 01-make-ruby27-pkg.sh, puis le pousse vers l'hôte web qui le sert.
#
#   - aloli-pkg.key  = clé PRIVÉE de signature → SECRÈTE, hors dépôt git, sauvegardée.
#   - aloli-pkg.pub  = clé PUBLIQUE → à coller dans la recette ruby27-aloli (sûre à diffuser).
set -eu

REPO=${REPO:-/root/aloli-repo-build/out}
KEYS=${KEYS:-/root/aloli-repo-build/keys}
# Destination de publication (hôte web servant le dépôt en HTTPS). À ADAPTER.
PUBLISH=${PUBLISH:-deploy@pkg.aloli.fr:/var/www/pkg/freebsd15/}

mkdir -p "$KEYS"

# --- 1. Génération des clés (idempotent : ne régénère pas si présent) ---
if [ ! -f "$KEYS/aloli-pkg.key" ]; then
  echo "Génération de la paire de clés RSA 4096…"
  openssl genrsa -out "$KEYS/aloli-pkg.key" 4096
  chmod 0400 "$KEYS/aloli-pkg.key"
  openssl rsa -in "$KEYS/aloli-pkg.key" -out "$KEYS/aloli-pkg.pub" -pubout
  echo
  echo ">>> COLLEZ le contenu suivant dans recipes/ruby27-aloli.recipe.yml"
  echo ">>> (bloc 'content:' de la clé publique) :"
  echo "-------------------------------------------------------------------"
  cat "$KEYS/aloli-pkg.pub"
  echo "-------------------------------------------------------------------"
else
  echo "Clés déjà présentes dans $KEYS (ok)."
fi

# --- 2. Signature du catalogue du dépôt ---
#   `pkg repo <dir> <clé_privée>` scanne les .pkg, génère meta/data et signe.
pkg repo "$REPO" "$KEYS/aloli-pkg.key"
echo "Dépôt signé : $REPO"

# --- 3. Publication vers l'hôte web (HTTPS) ---
echo "Publication vers $PUBLISH …"
rsync -a --delete "$REPO/" "$PUBLISH"
echo "Publié. Le dépôt doit être servi en HTTPS à l'URL configurée dans la recette."
