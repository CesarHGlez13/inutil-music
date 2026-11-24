#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <flutter-bundle> <version> <output-directory>" >&2
  exit 64
fi

bundle="$(realpath "$1")"
version="$2"
output_dir="$(mkdir -p "$3" && realpath "$3")"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# El bundle de Flutter trae el entry point que espera el tool (`inutil_music`,
# hoy un script) y el binario real con nombre legible (`Inútil Music`, el que
# muestra KDE/PipeWire). Se aceptan también los nombres heredados de Inutil
# para poder empaquetar bundles de checks anteriores.
launcher=""
for candidate in inutil_music inutil_music; do
  if [[ -e "$bundle/$candidate" ]]; then launcher="$candidate"; break; fi
done
if [[ -z "$launcher" ]]; then
  echo "Flutter Linux launcher not found at $bundle" >&2
  exit 1
fi

executable=""
for candidate in "Inútil Music" "Inútil Music"; do
  if [[ -x "$bundle/$candidate" ]]; then executable="$candidate"; break; fi
done
if [[ -z "$executable" ]]; then
  echo "Flutter Linux executable not found at $bundle" >&2
  exit 1
fi

if [[ -e "$bundle/tools" || -e "$bundle/scripts" ]]; then
  echo "Unexpected external-runtime directory in bundle: $bundle" >&2
  exit 1
fi

unexpected_media_tool="$(
  find "$bundle" -mindepth 1 \
    \( -iname 'ffmpeg*' -o -iname 'ffprobe*' \) \
    -print -quit
)"
if [[ -n "$unexpected_media_tool" ]]; then
  echo "Unexpected external media tool in bundle: $unexpected_media_tool" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

stage="$work_dir/root"
install -d \
  "$stage/opt/inutil-music" \
  "$stage/usr/bin" \
  "$stage/usr/share/applications" \
  "$stage/usr/share/icons/hicolor/512x512/apps"
cp -a "$bundle/." "$stage/opt/inutil-music/"
# El entry point que escribe Flutter repite el `BINARY_NAME` del CMake, así que
# al tener el binario real renombrado (`OUTPUT_NAME`) se exec a sí mismo en vez
# de arrancar la app. Se reescribe aquí para que apunte al ejecutable legible.
cat >"$stage/opt/inutil-music/$launcher" <<EOF
#!/bin/sh
set -e
exec "\$(dirname "\$0")/$executable" "\$@"
EOF
chmod 0755 "$stage/opt/inutil-music/$launcher"
install -m 0755 "$repo_root/packaging/linux/inutil-music" \
  "$stage/usr/bin/inutil-music"
install -m 0644 "$repo_root/packaging/linux/com.inutilmusic.app.desktop" \
  "$stage/usr/share/applications/com.inutilmusic.app.desktop"
install -m 0644 \
  "$repo_root/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png" \
  "$stage/usr/share/icons/hicolor/512x512/apps/com.inutilmusic.app.png"

deb_root="$work_dir/deb"
cp -a "$stage" "$deb_root"
install -d "$deb_root/DEBIAN"
cat >"$deb_root/DEBIAN/control" <<EOF
Package: inutil-music
Version: $version
Section: sound
Priority: optional
Architecture: amd64
Maintainer: Cesar <cesar@inutilmusic.com>
Depends: libgtk-3-0 | libgtk-3-0t64, libmpv2 | libmpv1, libsqlite3-0, libsecret-1-0, libc6, libstdc++6
Homepage: https://github.com/CesarHGlez13/inutil-music
Description: Reproductor y gestor musical multiplataforma
 Inútil Music permite buscar, reproducir, descargar y organizar musica,
 playlists y favoritos desde una interfaz construida con Flutter.
EOF
cat >"$deb_root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -f -t /usr/share/icons/hicolor || true
fi
exit 0
EOF
cat >"$deb_root/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -f -t /usr/share/icons/hicolor || true
fi
exit 0
EOF
chmod 0755 "$deb_root/DEBIAN/postinst" "$deb_root/DEBIAN/postrm"

deb_path="$output_dir/InutilMusic-$version-linux-amd64.deb"
dpkg-deb --root-owner-group --build "$deb_root" "$deb_path"
dpkg-deb --info "$deb_path"
dpkg-deb --contents "$deb_path" >/dev/null

rpm_top="$work_dir/rpmbuild"
if command -v rpmbuild >/dev/null 2>&1; then
  mkdir -p "$rpm_top"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
  rpmbuild -bb \
    --define "_topdir $rpm_top" \
    --define "app_version $version" \
    --define "staging_root $stage" \
    "$repo_root/packaging/linux/inutil-music.spec"

  rpm_source="$(find "$rpm_top/RPMS" -type f -name '*.rpm' -print -quit)"
  if [[ -z "$rpm_source" ]]; then
    echo "rpmbuild did not produce an RPM package" >&2
    exit 1
  fi

  rpm_path="$output_dir/InutilMusic-$version-linux-x86_64.rpm"
  cp "$rpm_source" "$rpm_path"
  rpm -qip "$rpm_path"
  rpm -qlp "$rpm_path" >/dev/null
  rpm -qpR "$rpm_path"
  printf 'Created:\n  %s\n  %s\n' "$deb_path" "$rpm_path"
else
  printf 'Created:\n  %s\n(rpmbuild omitido por no estar instalado)\n' "$deb_path"
fi
