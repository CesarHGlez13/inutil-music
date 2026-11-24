#!/usr/bin/env bash
# Prueba de extremo a extremo del auto-update de Linux.
#
# Extrae el script REAL embebido en InutilUpdateService
# (lib/core/firebase/inutil_update_service.dart) y lo ejecuta contra una
# instalación falsa, usando como staging el contenido del tar.gz generado por
# tool/package_linux.sh. Verifica que:
#   1. el helper espera a que muera el proceso de la app,
#   2. reemplanta binarios, data/ y lib/ sobre la instalación,
#   3. relanza el ejecutable nuevo,
#   4. borra el staging y no deja el helper instalado.
set -uo pipefail

PROY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBX="$HOME/.local/share/inutil-music-sandbox"
STG="$SBX-staging"
LOG="$HOME/.cache/inutil_music-sbx.log"
MARKER="$HOME/inutil_swap_marker.txt"
TARBALL="$PROY/dist/inutil_music_linux_x64.tar.gz"
SERVICE="$PROY/lib/core/firebase/inutil_update_service.dart"

[ -f "$TARBALL" ] || { echo "falta $TARBALL (ejecuta: flutter build linux --release && bash tool/package_linux.sh)" >&2; exit 3; }

rm -rf "$SBX" "$STG" "$LOG" "$MARKER"
mkdir -p "$SBX/data" "$SBX/lib" "$HOME/.cache"

# Instalación "vieja": ejecutable que anota su versión al arrancar.
printf '#!/usr/bin/env bash\necho "version-vieja" >> "%s"\n' "$MARKER" > "$SBX/Inutix Music"
chmod +x "$SBX/Inutix Music"
echo "dato viejo" > "$SBX/data/asset"
echo "lib vieja" > "$SBX/lib/libghostty_vte.so"

# Staging = contenido real del paquete nuevo. El ejecutable se sustituye por un
# stub para no abrir la app de verdad durante la prueba.
mkdir -p "$STG"
tar -xzf "$TARBALL" -C "$STG"
printf '#!/usr/bin/env bash\necho "version-nueva relanzada" >> "%s"\n' "$MARKER" > "$STG/Inutix Music"
chmod +x "$STG/Inutix Music"

# El script embebido se extrae del código Dart (mismo nombre de archivo que usa
# la app en producción: inutil_update_apply.sh dentro del staging).
python3 - "$SERVICE" "$STG/inutil_update_apply.sh" <<'PY'
import pathlib, re, sys

src = pathlib.Path(sys.argv[1]).read_text()
blocks = re.findall(r"r'''(.*?)'''", src, re.S)
candidates = [b for b in blocks if "STAGING" in b and "cp -a" in b]
assert candidates, "no se encontró el script de actualización embebido"
pathlib.Path(sys.argv[2]).write_text(candidates[0])
PY
chmod +x "$STG/inutil_update_apply.sh"
echo -n "líneas del script embebido: "; wc -l < "$STG/inutil_update_apply.sh"

# Proceso simulado de la app: vive 3 segundos y muere.
sleep 3 &
APP_PID=$!

mkdir -p "$(dirname "$LOG")"
setsid /bin/sh "$STG/inutil_update_apply.sh" "$APP_PID" "$STG" "$SBX" "$SBX/Inutix Music" > "$LOG" 2>&1 &

echo "helper lanzado; esperando a que muera el proceso simulado (pid $APP_PID)..."
wait $APP_PID 2>/dev/null || true
sleep 3

FAIL=0
echo "--- log del helper ---"; cat "$LOG" 2>/dev/null
echo "--- marcador ---"
if grep -q "version-nueva relanzada" "$MARKER" 2>/dev/null; then
  echo "OK: el ejecutable del paquete nuevo se relanzó"
else
  echo "MAL: el relanzamiento no ocurrió"; FAIL=1
fi

echo "--- instalación después ---"; ls "$SBX"
if grep -q "dato viejo" "$SBX/data/asset" 2>/dev/null; then
  echo "MAL: quedó un archivo de la instalación vieja en data/"; FAIL=1
else
  echo "OK: data/ convergida a la del paquete nuevo"
fi
if [ -d "$SBX/data/flutter_assets" ]; then
  echo "OK: data/flutter_assets instalado"
else
  echo "MAL: falta data/flutter_assets del paquete nuevo"; FAIL=1
fi
if [ -f "$SBX/lib/libghostty_vte.so" ]; then
  echo "MAL: la lib falsa sigue ahí"; FAIL=1
else
  echo -n "OK: lib/ convergida (ahora contiene: "; ls "$SBX/lib" | head -3 | tr '\n' ' '; echo ")"
fi
if [ -d "$STG" ]; then echo "MAL: el staging sigue existiendo"; FAIL=1; else echo "OK: staging eliminado"; fi
if [ -f "$SBX/inutil_update_apply.sh" ]; then echo "MAL: el helper quedó instalado"; FAIL=1; else echo "OK: el helper no queda en la instalación"; fi

head -2 "$SBX/Inutix Music" | tail -1 | grep -q "version-nueva" \
  && echo "OK: el ejecutable instalado es el del paquete nuevo" \
  || { echo "MAL: el ejecutable instalado no es el nuevo"; FAIL=1; }

[ "$FAIL" = "0" ] && echo "RESULTADO: PRUEBA SUPERADA" || echo "RESULTADO: FALLOS ($FAIL)"
exit $FAIL
