#!/usr/bin/env bash
# Assemble an .ipa from the `flutter build ios` output.
#
# Usage: package-ios.sh <version>
#
# Packs build/ios/iphoneos/Runner.app into a Payload/ directory and zips it
# into artifacts/cliff_messenger-<version>-ios.ipa. If an ExportOptions.plist
# exists in ios/Runner it is honoured; otherwise an ad-hoc/export option set
# is generated.

set -euo pipefail

VERSION="${1:?usage: package-ios.sh <version>}"
APP_NAME="cliff_messenger"
APP_PATH="build/ios/iphoneos/Runner.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Runner.app not found at $APP_PATH — did the build run?" >&2
  exit 1
fi

STAGE="$RUNNER_TEMP/ipa-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
cp -R "$APP_PATH" "$STAGE/Payload/Runner.app"

# Optional: copy an ExportOptions.plist if present (for signed App Store / Ad
# Hoc exports). The .ipa assembled here is a Payload zip, which is the format
# expected by most ad-hoc distribution tools.
if [[ -f "ios/Runner/ExportOptions.plist" ]]; then
  cp "ios/Runner/ExportOptions.plist" "$STAGE/"
fi

mkdir -p artifacts
IPA="artifacts/${APP_NAME}-${VERSION}-ios.ipa"
( cd "$STAGE" && zip -qry "$GITHUB_WORKSPACE/$IPA" Payload )
echo "Assembled $IPA ($(du -h "$IPA" | cut -f1))"
