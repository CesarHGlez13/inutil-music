#!/usr/bin/env bash
# Empaqueta el release de Linux para la actualización OTA dentro de la app.
#
# El archivo resultante se publica en `app_config/release` como
# `linuxDownloadUrl`; InutilUpdateService lo descarga, lo descomprime y
# reemplanta el bundle en ~/.local/share/inutil-music. Por eso el tar debe
# contener el contenido del bundle en la raíz («Inutix Music», data/, lib/,
# THIRD_PARTY_NOTICES.md), sin carpetas intermedias.
#
# Uso: tool/package_linux.sh [salida.tar.gz]
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$repo_root/dist/inutil_music_linux_x64.tar.gz}"
bundle="$repo_root/build/linux/x64/release/bundle"
executable="$bundle/Inutix Music"

if [[ ! -x "$executable" ]]; then
  echo "Falta el bundle. Ejecuta antes: flutter build linux --release" >&2
  exit 1
fi

# Copiar libmpv.so.2 dentro de bundle/lib si existe en el sistema para que el paquete sea 100% autónomo
if [[ ! -f "$bundle/lib/libmpv.so.2" ]]; then
  for candidate in \
    /usr/lib/x86_64-linux-gnu/libmpv.so.2 \
    /usr/lib64/libmpv.so.2 \
    /usr/lib/libmpv.so.2; do
    if [[ -f "$candidate" ]]; then
      cp -L "$candidate" "$bundle/lib/libmpv.so.2"
      echo "Incustrada librería libmpv: $candidate -> $bundle/lib/libmpv.so.2"
      break
    fi
  done
fi

# Actualizar el lanzador inutil_music para cargar las librerías locales
cat >"$bundle/inutil_music" <<'EOF'
#!/bin/sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$DIR/lib:$DIR/mpv_libs:${LD_LIBRARY_PATH:-}"
if [ -f "$DIR/lib/libmpv.so.2" ]; then
  export LIBMPV_LIBRARY_PATH="$DIR/lib/libmpv.so.2"
fi
exec "$DIR/Inutix Music" "$@"
EOF
chmod 0755 "$bundle/inutil_music"

# Incluir install.sh en el paquete si existe en la raíz del repo
repo_root_installer="$repo_root/install.sh"
if [[ -f "$repo_root_installer" ]]; then
  cp "$repo_root_installer" "$bundle/install.sh"
  chmod 0755 "$bundle/install.sh"
fi

mkdir -p "$(dirname "$output")"
tar -czf "$output" -C "$bundle" \
  "Inutix Music" \
  inutil_music \
  data \
  lib \
  THIRD_PARTY_NOTICES.md \
  $([ -f "$bundle/install.sh" ] && echo install.sh || true)

echo "Paquete OTA: $output ($(du -h "$output" | cut -f1))"
tar -tzf "$output" | head -5 || true
