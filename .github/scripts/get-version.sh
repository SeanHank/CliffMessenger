#!/usr/bin/env bash
# Resolve the build version & metadata, then expose them as step outputs.
#
# Priority: workflow_dispatch input > git tag (v*) > pubspec.yaml `version:`.
# Outputs (via GITHUB_OUTPUT):
#   version        — semantic version (e.g. 2026.4.6)
#   build_number   — integer build number derived from version
#   tag            — git tag name to create (e.g. v2026.4.6)
#   is_release     — "true" if triggered by tag or manual dispatch
#   should_release — "true" if a GitHub Release should be published

set -euo pipefail

INPUT_VERSION=""
REF=""
EVENT=""
CREATE_RELEASE="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input-version)  INPUT_VERSION="$2"; shift 2 ;;
    --ref)            REF="$2"; shift 2 ;;
    --event)          EVENT="$2"; shift 2 ;;
    --create-release) CREATE_RELEASE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Read version from pubspec.yaml (first `version:` line).
read_pubspec_version() {
  grep -m1 '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*//; s/\+.*//'
}

# Convert a semver string (x.y.z) into an integer build number.
# e.g. 2026.4.6 -> 20260406  (pads each component to 2 digits)
version_to_build_number() {
  local v="$1"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$v"
  major="${major:-0}"
  minor="${minor:-0}"
  patch="${patch:-0}"
  printf '%d%02d%02d' "$major" "$minor" "$patch"
}

VERSION=""
TAG=""
IS_RELEASE="false"
SHOULD_RELEASE="false"

# 1. workflow_dispatch input version
if [[ -n "$INPUT_VERSION" ]]; then
  VERSION="$INPUT_VERSION"
  IS_RELEASE="true"
fi

# 2. git tag push (refs/tags/v*)
if [[ -z "$VERSION" && "$REF" == refs/tags/v* ]]; then
  VERSION="${REF#refs/tags/v}"
  TAG="v${VERSION}"
  IS_RELEASE="true"
fi

# 3. Fall back to pubspec.yaml
if [[ -z "$VERSION" ]]; then
  VERSION="$(read_pubspec_version)"
fi

# Ensure a tag exists for release publishing.
if [[ -z "$TAG" ]]; then
  TAG="v${VERSION}"
fi

# Decide whether to publish a Release:
#   - tag push           → always
#   - workflow_dispatch  → honour the create_release input
#   - pull_request       → never
case "$EVENT" in
  pull_request)
    IS_RELEASE="false"
    SHOULD_RELEASE="false"
    ;;
  workflow_dispatch)
    IS_RELEASE="true"
    [[ "$CREATE_RELEASE" == "true" ]] && SHOULD_RELEASE="true" || SHOULD_RELEASE="false"
    ;;
  push)
    [[ "$REF" == refs/tags/v* ]] && SHOULD_RELEASE="true"
    ;;
esac

BUILD_NUMBER="$(version_to_build_number "$VERSION")"

{
  echo "version=$VERSION"
  echo "build_number=$BUILD_NUMBER"
  echo "tag=$TAG"
  echo "is_release=$IS_RELEASE"
  echo "should_release=$SHOULD_RELEASE"
} >> "$GITHUB_OUTPUT"

echo "Resolved version=$VERSION build_number=$BUILD_NUMBER tag=$TAG is_release=$IS_RELEASE should_release=$SHOULD_RELEASE"
