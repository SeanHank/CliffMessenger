#!/usr/bin/env bash
# Package the macOS .app bundle into a distributable zip.
#
# Usage: package-macos.sh <version>
#
# Locates build/macos/Build/Products/Release/*.app and zips it (preserving the
# .app bundle structure) into artifacts/cliff_messenger-<version>-macos.zip.

set -euo pipefail

VERSION="${1:?usage: package-macos.sh <version>}"
APP_NAME="cliff_messenger"
APP_DIR="build/macos/Build/Products/Release"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Release products dir not found: $APP_DIR" >&2
  exit 1
fi

APP_PATH="$(find "$APP_DIR" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "No .app bundle found under $APP_DIR" >&2
  exit 1
fi

APP_BASENAME="$(basename "$APP_PATH")"
mkdir -p artifacts
ZIP="artifacts/${APP_NAME}-${VERSION}-macos.zip"

# Zip from inside the products dir so the .app is at the archive root.
( cd "$APP_DIR" && ditto -c -k --keepParent "$APP_BASENAME" "$GITHUB_WORKSPACE/$ZIP" )

echo "Packaged $ZIP ($(du -h "$ZIP" | cut -f1))"
