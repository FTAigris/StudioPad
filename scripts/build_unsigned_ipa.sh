#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DIR="$PROJECT_DIR/build/DerivedData"
PACKAGE_DIR="$PROJECT_DIR/build/ipa"

command -v xcodegen >/dev/null 2>&1 || {
  echo "Falta XcodeGen. Instálalo antes de continuar."
  exit 1
}

cd "$PROJECT_DIR"
xcodegen generate --spec project.yml

xcodebuild \
  -project StudioPad.xcodeproj \
  -scheme StudioPad \
  -resolvePackageDependencies

xcodebuild \
  -project StudioPad.xcodeproj \
  -scheme StudioPad \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DIR/Build/Products/Release-iphoneos/StudioPad.app"
test -d "$APP_PATH"

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/Payload"
cp -R "$APP_PATH" "$PACKAGE_DIR/Payload/StudioPad.app"

cd "$PACKAGE_DIR"
zip -qry "$PROJECT_DIR/build/StudioPad-unsigned.ipa" Payload
echo "IPA creado en $PROJECT_DIR/build/StudioPad-unsigned.ipa"

