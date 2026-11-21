#!/usr/bin/env bash
# Empaqueta el release de Linux para la actualización OTA dentro de la app.
#
# El archivo resultante se publica en `app_config/release` como
# `linuxDownloadUrl`; InutilUpdateService lo descarga, lo descomprime y
# reemplanta el bundle en ~/.local/share/inutil-music. Por eso el tar debe
# contener el contenido del bundle en la raíz («Inútil Music», data/, lib/,
# THIRD_PARTY_NOTICES.md), sin carpetas intermedias.
#
# Uso: tool/package_linux.sh [salida.tar.gz]
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$repo_root/dist/inutil_music_linux_x64.tar.gz}"
bundle="$repo_root/build/linux/x64/release/bundle"
executable="$bundle/Inútil Music"

if [[ ! -x "$executable" ]]; then
  echo "Falta el bundle. Ejecuta antes: flutter build linux --release" >&2
  exit 1
fi

mkdir -p "$(dirname "$output")"
tar -czf "$output" -C "$bundle" \
  "Inútil Music" \
  data \
  lib \
  THIRD_PARTY_NOTICES.md

echo "Paquete OTA: $output ($(du -h "$output" | cut -f1))"
tar -tzf "$output" | head -5
