#!/usr/bin/env bash
# Configure iOS code signing from GitHub secrets.
#
# Required secrets (env):
#   P12_BASE64            — base64-encoded signing certificate (.p12)
#   P12_PASSWORD          — password for the .p12
#   PROVISION_BASE64      — base64-encoded provisioning profile (.mobileprovision)
#
# Imports the certificate into the default keychain and installs the profile.
# The Xcode project must have DEVELOPMENT_TEAM / PROVISIONING_PROFILE_UUID
# configured (or ExportOptions.plist present) for `flutter build ios` to pick
# them up.

set -euo pipefail

if [[ -z "${P12_BASE64:-}" ]]; then
  echo "P12_BASE64 not set — skipping iOS signing setup."
  exit 0
fi

: "${P12_PASSWORD:?IOS_P12_PASSWORD secret is required}"
: "${PROVISION_BASE64:?IOS_PROVISIONING_PROFILE_BASE64 secret is required}"

# --- 1. Import certificate into the login keychain -----------------------
P12_PATH="$RUNNER_TEMP/build_cert.p12"
CERT_PASSWORD="$P12_PASSWORD"
KEYCHAIN_PATH="$RUNNER_TEMP/app-signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"

echo "$P12_BASE64" | base64 --decode > "$P12_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

security import "$P12_PATH" -P "$CERT_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

echo "Imported signing certificate into $KEYCHAIN_PATH"

# --- 2. Install provisioning profile -------------------------------------
PROVISION_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROVISION_DIR"

PROVISION_PATH="$RUNNER_TEMP/profile.mobileprovision"
echo "$PROVISION_BASE64" | base64 --decode > "$PROVISION_PATH"

# Derive the UUID from the profile plist.
UUID=$(/usr/libexec/PlistBuddy -c "Print UUID" /dev/stdin \
  <<< "$(security cms -D -i "$PROVISION_PATH")")
cp "$PROVISION_PATH" "$PROVISION_DIR/$UUID.mobileprovision"
echo "Installed provisioning profile UUID=$UUID"

# Expose for downstream steps.
echo "IOS_PROVISIONING_UUID=$UUID" >> "$GITHUB_ENV"
