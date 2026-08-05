#!/usr/bin/env bash
# Configure Android release signing from GitHub secrets.
#
# Required secrets (env):
#   KEYSTORE_BASE64          — base64-encoded release keystore (.jks/.keystore)
#   ANDROID_KEYSTORE_PASSWORD
#   ANDROID_KEY_ALIAS
#   ANDROID_KEY_PASSWORD
#
# Writes a key.properties next to the android/ app gradle module and patches
# android/app/build.gradle.kts to use it for the release build type.

set -euo pipefail

if [[ -z "${KEYSTORE_BASE64:-}" ]]; then
  echo "KEYSTORE_BASE64 not set — skipping signing setup (unsigned build)."
  exit 0
fi

: "${ANDROID_KEYSTORE_PASSWORD:?ANDROID_KEYSTORE_PASSWORD secret is required}"
: "${ANDROID_KEY_ALIAS:?ANDROID_KEY_ALIAS secret is required}"
: "${ANDROID_KEY_PASSWORD:?ANDROID_KEY_PASSWORD secret is required}"

KEYSTORE_PATH="$HOME/cliff-release.jks"
echo "$KEYSTORE_BASE64" | base64 --decode > "$KEYSTORE_PATH"
echo "Keystore written to $KEYSTORE_PATH ($(stat -c%s "$KEYSTORE_PATH") bytes)"

# Write key.properties (read by the gradle signing config).
cat > android/key.properties <<EOF
storePassword=$ANDROID_KEYSTORE_PASSWORD
keyPassword=$ANDROID_KEY_PASSWORD
keyAlias=$ANDROID_KEY_ALIAS
storeFile=$KEYSTORE_PATH
EOF
echo "Wrote android/key.properties"

# Patch android/app/build.gradle.kts: replace the debug signingConfig in the
# release build type with a keystore-backed one. Only patch once.
GRADLE_FILE="android/app/build.gradle.kts"
if ! grep -q "key.properties" "$GRADLE_FILE"; then
  python3 - "$GRADLE_FILE" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
# Inject a signingConfigs block reading key.properties just before `android {`.
inject = '''    val keystoreProperties = java.util.Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
    }
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
'''
src = src.replace("    defaultConfig {", inject + "    defaultConfig {", 1)
# Point release build type at the release signing config.
src = src.replace(
    "signingConfig = signingConfigs.getByName(\"debug\")",
    "signingConfig = signingConfigs.getByName(\"release\")",
)
p.write_text(src)
print("Patched", sys.argv[1], "for release signing")
PY
else
  echo "build.gradle.kts already references key.properties — skipping patch."
fi
