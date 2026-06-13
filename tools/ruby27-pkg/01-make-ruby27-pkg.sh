#!/bin/sh
# 01-make-ruby27-pkg.sh — À EXÉCUTER SUR `han` (FreeBSD 15, en root).
#
# Repackage l'arbre Ruby 2.7.8 DÉJÀ compilé et validé in vivo
# (/opt/rubies/ruby-2.7.8) en paquet pkg binaire, SANS recompiler, et fige
# openssl111 dans le même répertoire de dépôt. Le but : build une fois ici,
# déployé en pkg sur les ~20 serveurs (cf. recette ruby27-aloli).
#
# Pré-requis : /opt/rubies/ruby-2.7.8 présent (script install-ruby-2.7.sh) et
# openssl111 encore disponible dans le dépôt FreeBSD-ports (à capturer MAINTENANT,
# il est déprécié et programmé pour retrait).
set -eu

PREFIX=/opt/rubies/ruby-2.7.8
REPO=${REPO:-/root/aloli-repo-build/out}   # répertoire de dépôt (sortie)
VERSION=2.7.8
OSSL_VERSION=${OSSL_VERSION:-1.1.1w_2}      # version exacte d'openssl111 installée

[ -x "$PREFIX/bin/ruby" ] || { echo "ABSENT : $PREFIX/bin/ruby — lancez d'abord install-ruby-2.7.sh" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$REPO"

# --- 1. Liste des fichiers (relative au prefix = forme canonique pkg) ---
( cd "$PREFIX" && find . \( -type f -o -type l \) | sed 's|^\./||' ) | sort > "$work/pkg-plist"
echo "plist : $(wc -l < "$work/pkg-plist") entrées"

# --- 2. Manifeste UCL ---
cat > "$work/+MANIFEST" <<EOF
name: ruby27-aloli
version: "$VERSION"
origin: lang/ruby27-aloli
comment: "Ruby $VERSION (build interne Aloli, patch FreeBSD15 qsort_r, lié openssl111)"
maintainer: it@aloli.fr
www: "https://www.ruby-lang.org/"
prefix: "$PREFIX"
desc: "Ruby $VERSION recompilé en interne pour FreeBSD 15 (patch util.c qsort_r + OpenSSL 1.1.1). Posé tel quel dans $PREFIX, découvert par chruby. Dépendance transitoire le temps de migrer hors Ruby 2.7."
deps: {
  openssl111: { origin: "security/openssl111", version: "$OSSL_VERSION" }
}
EOF

# --- 3. Création du paquet binaire (PAS de recompilation) ---
pkg create -r "$PREFIX" -M "$work/+MANIFEST" -p "$work/pkg-plist" -o "$REPO"
echo "pkg ruby27-aloli créé dans $REPO"

# --- 4. Figer openssl111 (+ deps) dans le même dépôt, tant qu'il existe upstream ---
pkg fetch -y -o "$REPO" -d openssl111
echo "openssl111 figé dans $REPO/All"

echo
echo "OK. Contenu du dépôt :"
find "$REPO" -name '*.pkg' -o -name '*.txz' | sort
echo
echo "=> Étape suivante : 02-build-repo.sh (signature + publication)."
