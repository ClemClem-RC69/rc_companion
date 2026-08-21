#!/bin/zsh
set -euo pipefail

APK_SOURCE="build/app/outputs/flutter-apk/app-release.apk"

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)

if [[ -z "${VERSION}" ]]; then
  echo "Erreur : impossible de lire la version dans pubspec.yaml"
  exit 1
fi

APK_NAME="RC Companion Android ${VERSION}.apk"
APK_DEST="${HOME}/Desktop/RC Companion/Perso/${APK_NAME}"

if [[ ! -f "${APK_SOURCE}" ]]; then
  echo "Erreur : APK Release introuvable : ${APK_SOURCE}"
  echo "Lance d'abord : flutter build apk --release ..."
  exit 1
fi

mkdir -p "$(dirname "${APK_DEST}")"
cp "${APK_SOURCE}" "${APK_DEST}"

echo ""
echo "APK créé avec succès :"
ls -lh "${APK_DEST}"
