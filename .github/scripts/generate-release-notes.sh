#!/usr/bin/env bash
# Generate a Markdown release-notes body for a given version.
#
# Usage: generate-release-notes.sh <version> <display_name>
# Output is written to stdout — pipe to a file in the caller.

set -euo pipefail

VERSION="${1:?usage: generate-release-notes.sh <version> <display_name>}"
DISPLAY_NAME="${2:?missing display_name}"
REPO="${GITHUB_REPOSITORY:-cliff_messenger}"
RUN_ID="${GITHUB_RUN_ID:-local}"
SHA="${GITHUB_SHA:-unknown}"

cat <<EOF
## ${DISPLAY_NAME} ${VERSION}

Automated multi-platform build. See the artifacts attached to this release for
each platform's distributable.

### Downloads

| Platform | File |
|----------|------|
| Android (>= 9)    | \`cliff_messenger-${VERSION}-android.apk\` |
| iOS (>= 14)       | \`cliff_messenger-${VERSION}-ios.ipa\` |
| macOS             | \`cliff_messenger-${VERSION}-macos.zip\` |
| Linux (.deb)      | \`cliff_messenger-${VERSION}-amd64.deb\` |
| Linux (.rpm)      | \`cliff_messenger-${VERSION}-x86_64.rpm\` |
| Windows (>= 10)   | \`cliff_messenger-${VERSION}-windows.zip\` |

### Security notes

- iOS/macOS artifacts in releases without code-signing secrets are **unsigned**.
  Install them only if you trust the build source; otherwise build from source
  or use a signed release.
- Android APK is signed with the debug key by default unless the
  \`ANDROID_KEYSTORE_BASE64\` secret is configured.
- Linux packages depend on \`libgtk-3-0\`, \`libsqlcipher0\`, \`liblzma5\`.

### Build provenance

- Commit: \`${SHA:0:12}\`
- Workflow run: https://github.com/${REPO}/actions/runs/${RUN_ID}
EOF
