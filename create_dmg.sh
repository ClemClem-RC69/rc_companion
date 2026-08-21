#!/bin/zsh
set -euo pipefail

APP_NAME="RC Companion"
APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)

if [[ -z "${VERSION}" ]]; then
  echo "Erreur : impossible de lire la version dans pubspec.yaml"
  exit 1
fi

DMG_NAME="RC Companion ${VERSION}.dmg"
DMG_TEMP="build/macos/${DMG_NAME}"
DMG_DEST="${HOME}/Desktop/RC Companion/Perso/${DMG_NAME}"

STAGING_DIR="build/macos/dmg_staging"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Erreur : application introuvable : ${APP_PATH}"
  echo "Lance d'abord : flutter build macos --release"
  exit 1
fi

echo "Version détectée : ${VERSION}"
echo "Préparation du DMG…"

rm -rf "${STAGING_DIR}"
rm -f "${DMG_TEMP}"

mkdir -p "${STAGING_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_TEMP}"

mkdir -p "$(dirname "${DMG_DEST}")"
cp "${DMG_TEMP}" "${DMG_DEST}"

rm -rf "${STAGING_DIR}"

echo ""
echo "DMG créé avec succès :"
ls -lh "${DMG_DEST}"
