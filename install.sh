#!/usr/bin/env bash
# Inutix Music - Instalador automático para Linux (Ubuntu, Debian, Fedora, Arch, etc.)
# No requiere privilegios de root (instala en el espacio de usuario ~/.local).
# Compatible con ejecución directa (bash install.sh) y por pipe (curl | bash).
set -euo pipefail

APP_NAME="Inutix Music"
VERSION="2.5.28"
INSTALL_DIR="$HOME/.local/share/inutil-music"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"
DOWNLOAD_URL="https://github.com/CesarHGlez13/inutil-music/releases/download/v${VERSION}/inutil_music_linux_x64.tar.gz"

echo "========================================="
echo " Instalador de $APP_NAME (v$VERSION)"
echo "========================================="

# 1. Verificar arquitectura
ARCH="$(uname -m)"
if [[ "$ARCH" != "x86_64" ]]; then
  echo "Error: Esta versión está compilada para x86_64 (amd64). Arquitectura detectada: $ARCH" >&2
  exit 1
fi

# 2. Crear directorios necesarios
mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"

# 3. Obtener los archivos de la app
# BASH_SOURCE[0] puede no estar definido cuando se ejecuta por pipe (curl|bash).
# En ese caso, se descarga directamente desde GitHub. Si se ejecuta como archivo
# y el bundle ya existe junto al script, se instala desde local.
LOCAL_BUNDLE=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  _SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
  if [[ -n "$_SDIR" && -x "$_SDIR/build/linux/x64/release/bundle/Inutix Music" ]]; then
    LOCAL_BUNDLE="$_SDIR/build/linux/x64/release/bundle"
  elif [[ -n "$_SDIR" && -x "$_SDIR/Inutix Music" ]]; then
    LOCAL_BUNDLE="$_SDIR"
  fi
fi

if [[ -n "$LOCAL_BUNDLE" ]]; then
  echo "--> Instalando desde copia local ($LOCAL_BUNDLE)..."
  cp -a "$LOCAL_BUNDLE/." "$INSTALL_DIR/"
else
  echo "--> Descargando paquete completo v$VERSION desde GitHub..."
  TMP_TAR="$(mktemp --suffix=.tar.gz)"
  trap 'rm -f "$TMP_TAR"' EXIT
  if command -v curl >/dev/null 2>&1; then
    curl -fSL "$DOWNLOAD_URL" -o "$TMP_TAR"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP_TAR" "$DOWNLOAD_URL"
  else
    echo "Error: Se requiere curl o wget para descargar la aplicación." >&2
    exit 1
  fi
  echo "--> Descomprimiendo en $INSTALL_DIR..."
  tar -xzf "$TMP_TAR" -C "$INSTALL_DIR"
fi

# 4. Asegurar permisos de ejecución
chmod +x "$INSTALL_DIR/Inutix Music" 2>/dev/null || true
if [[ -f "$INSTALL_DIR/inutil_music" ]]; then
  chmod +x "$INSTALL_DIR/inutil_music"
fi

# 5. Instalar lanzador de terminal en ~/.local/bin/inutil-music
cat >"$BIN_DIR/inutil-music" <<'EOF'
#!/bin/sh
DIR="$HOME/.local/share/inutil-music"
export LD_LIBRARY_PATH="$DIR/lib:$DIR/mpv_libs:${LD_LIBRARY_PATH:-}"
if [ -f "$DIR/lib/libmpv.so.2" ]; then
  export LIBMPV_LIBRARY_PATH="$DIR/lib/libmpv.so.2"
fi
exec "$DIR/Inutix Music" "$@"
EOF
chmod 0755 "$BIN_DIR/inutil-music"

# 6. Instalar icono de alta resolución
ICON_SRC=""
if [[ -f "$INSTALL_DIR/data/flutter_assets/assets/icons/inutil_icon.png" ]]; then
  ICON_SRC="$INSTALL_DIR/data/flutter_assets/assets/icons/inutil_icon.png"
elif [[ -f "$INSTALL_DIR/data/com.inutilmusic.app.png" ]]; then
  ICON_SRC="$INSTALL_DIR/data/com.inutilmusic.app.png"
fi

if [[ -n "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$ICON_DIR/com.inutilmusic.app.png"
  chmod 0644 "$ICON_DIR/com.inutilmusic.app.png"
fi

# 7. Instalar acceso directo en el menú de aplicaciones (.desktop)
cat >"$DESKTOP_DIR/inutil-music.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Inutix Music
Comment=Reproductor y gestor musical multiplataforma
Exec=$BIN_DIR/inutil-music %u
Icon=com.inutilmusic.app
Terminal=false
Categories=AudioVideo;Audio;Player;Music;
StartupWMClass=com.inutilmusic.app
MimeType=x-scheme-handler/inutilmusic;text/csv;text/comma-separated-values;application/csv;
EOF
chmod 0644 "$DESKTOP_DIR/inutil-music.desktop"

# 8. Actualizar base de datos de escritorio e iconos
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi

# 9. Verificar dependencia de reproducción de audio (libmpv)
if ! ldconfig -p 2>/dev/null | grep -q 'libmpv\.so'; then
  if [[ ! -d "$INSTALL_DIR/mpv_libs" && ! -f "$INSTALL_DIR/lib/libmpv.so.2" ]]; then
    echo "-----------------------------------------"
    echo " Nota: Se requiere libmpv para reproducir audio."
    if command -v apt-get >/dev/null 2>&1; then
      echo " Instálala fácilmente con: sudo apt install -y libmpv2"
    elif command -v dnf >/dev/null 2>&1; then
      echo " Instálala fácilmente con: sudo dnf install -y mpv-libs"
    elif command -v pacman >/dev/null 2>&1; then
      echo " Instálala fácilmente con: sudo pacman -S mpv"
    fi
    echo "-----------------------------------------"
  fi
fi

echo "========================================="
echo " ¡Instalación completada con éxito!"
echo " Inútil Music ya está disponible en tu menú de aplicaciones."
echo " O ejecuta directamente: inutil-music"
echo "========================================="
