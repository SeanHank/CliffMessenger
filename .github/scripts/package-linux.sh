#!/usr/bin/env bash
# Package the Flutter Linux build into .deb and .rpm distributables.
#
# Usage: package-linux.sh <version> <app_name> <display_name>
#
# Reads the bundle produced by `flutter build linux --release` at
# build/linux/x64/release/bundle/ and wraps it in Debian & RPM package layouts.

set -euo pipefail

VERSION="${1:?usage: package-linux.sh <version> <app_name> <display_name>}"
APP_NAME="${2:?missing app_name}"
DISPLAY_NAME="${3:?missing display_name}"

BUNDLE_DIR="build/linux/x64/release/bundle"
if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Linux bundle not found at $BUNDLE_DIR — did 'flutter build linux' run?" >&2
  exit 1
fi

ARCH="$(dpkg --print-architecture)"   # amd64 / arm64
INSTALL_DIR="/opt/${APP_NAME}"
mkdir -p artifacts

# ─────────────────────────────────────────────────────────────────────────
# .deb packaging
# ─────────────────────────────────────────────────────────────────────────
DEB_ROOT="$RUNNER_TEMP/deb-root"
rm -rf "$DEB_ROOT"
mkdir -p "$DEB_ROOT${INSTALL_DIR}/lib"
mkdir -p "$DEB_ROOT/usr/bin"
mkdir -p "$DEB_ROOT/usr/share/applications"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"

# Copy the bundle payload (binary + lib + data).
cp -r "$BUNDLE_DIR/." "$DEB_ROOT${INSTALL_DIR}/"

# Symlink the executable into /usr/bin for PATH access.
ln -sf "${INSTALL_DIR}/${APP_NAME}" "$DEB_ROOT/usr/bin/${APP_NAME}"

# .desktop entry.
cat > "$DEB_ROOT/usr/share/applications/${APP_NAME}.desktop" <<EOF
[Desktop Entry]
Name=${DISPLAY_NAME}
Comment=End-to-End Encrypted Messenger
Exec=${APP_NAME}
Icon=${APP_NAME}
Terminal=false
Type=Application
Categories=Network;InstantMessaging;Security;
EOF

# Icon (reuse the Flutter runner icon if present, else a placeholder).
ICON_SRC="linux/runner/resources/icon.png"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
fi

# Debian control metadata.
DEB_SIZE="$(du -sk "$DEB_ROOT" | cut -f1)"
mkdir -p "$DEB_ROOT/DEBIAN"
cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: ${APP_NAME}
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: Sean Hank <sean@cliff.example>
Installed-Size: ${DEB_SIZE}
Depends: libgtk-3-0, libsqlcipher0, liblzma5, libstdc++6
Section: net
Priority: optional
Description: ${DISPLAY_NAME}
 End-to-end encrypted, privacy-focused group messaging app built with Flutter.
EOF

cat > "$DEB_ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
EOF
chmod 0755 "$DEB_ROOT/DEBIAN/postinst"

DEB="artifacts/${APP_NAME}-${VERSION}-${ARCH}.deb"
dpkg-deb --build --root-owner-group "$DEB_ROOT" "$GITHUB_WORKSPACE/$DEB"
echo "Built $DEB ($(du -h "$DEB" | cut -f1))"

# ─────────────────────────────────────────────────────────────────────────
# .rpm packaging (using rpmbuild)
# ─────────────────────────────────────────────────────────────────────────
RPM_TOP="$RUNNER_TEMP/rpm-top"
rm -rf "$RPM_TOP"
mkdir -p "$RPM_TOP"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Build a clean source tarball from the original Flutter bundle payload.
# %setup will unpack it into a directory named ${APP_NAME}-${VERSION}/
RPM_STAGE="$RUNNER_TEMP/${APP_NAME}-${VERSION}"
rm -rf "$RPM_STAGE"
mkdir -p "$RPM_STAGE"
cp -r "$BUNDLE_DIR/." "$RPM_STAGE/"

# Stash the icon next to the payload so the spec can pick it up.
ICON_SRC="linux/runner/resources/icon.png"
[[ -f "$ICON_SRC" ]] && cp "$ICON_SRC" "$RPM_STAGE/app-icon.png"

TARBALL="${APP_NAME}-${VERSION}.tar.gz"
tar -czf "$RPM_TOP/SOURCES/$TARBALL" -C "$RUNNER_TEMP" "${APP_NAME}-${VERSION}"

RPM_ARCH="$ARCH"
[[ "$ARCH" == "amd64" ]] && RPM_ARCH="x86_64"

cat > "$RPM_TOP/SPECS/${APP_NAME}.spec" <<EOF
Name:           ${APP_NAME}
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        ${DISPLAY_NAME}
License:        Proprietary
URL:            https://github.com/${GITHUB_REPOSITORY}
Source0:        %{name}-%{version}.tar.gz
BuildArch:      ${RPM_ARCH}
Requires:       gtk3, sqlcipher, xz-libs, libstdc++

%description
End-to-end encrypted, privacy-focused group messaging app built with Flutter.

%prep
%setup -q

%install
mkdir -p %{buildroot}${INSTALL_DIR}
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps
# Copy the Flutter bundle (binary + lib + data) into the install prefix.
cp -r . %{buildroot}${INSTALL_DIR}/
# Symlink the executable into /usr/bin.
ln -sf ${INSTALL_DIR}/${APP_NAME} %{buildroot}/usr/bin/${APP_NAME}
# .desktop entry.
cat > %{buildroot}/usr/share/applications/${APP_NAME}.desktop <<DESKTOP
[Desktop Entry]
Name=${DISPLAY_NAME}
Comment=End-to-End Encrypted Messenger
Exec=${APP_NAME}
Icon=${APP_NAME}
Terminal=false
Type=Application
Categories=Network;InstantMessaging;Security;
DESKTOP
# Icon (if staged).
if [ -f app-icon.png ]; then
  cp app-icon.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png
fi

%files
${INSTALL_DIR}
/usr/bin/${APP_NAME}
/usr/share/applications/${APP_NAME}.desktop
/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png

%post
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true

%changelog
* $(date '+a %b %d %Y') Sean Hank - ${VERSION}-1
- Automated build ${VERSION}
EOF

rpmbuild -bb \
  --define "_topdir $RPM_TOP" \
  --target "$RPM_ARCH" \
  "$RPM_TOP/SPECS/${APP_NAME}.spec"

RPM_BUILT="$(find "$RPM_TOP/RPMS" -name "*.rpm" -print -quit)"
if [[ -n "$RPM_BUILT" ]]; then
  RPM="artifacts/${APP_NAME}-${VERSION}-${RPM_ARCH}.rpm"
  cp "$RPM_BUILT" "$GITHUB_WORKSPACE/$RPM"
  echo "Built $RPM ($(du -h "$RPM" | cut -f1))"
else
  echo "rpmbuild did not produce an .rpm" >&2
  exit 1
fi

echo "Linux packaging complete:"
ls -lh artifacts/
