#!/usr/bin/env bash
# Publica una versión de Inútil Music.
#
# Genera el manifiesto `release.json` (el que lee la app en
# InutilUpdateService.checkForUpdate) y, según el modo, coloca los artefactos:
#
#   --local      (por defecto) copia `.apk`/`.tar.gz` + release.json a
#                ~/inutil-releases/, la carpeta que la app sirve por HTTP en la
#                red local (/api/release y /api/releases/<archivo>). Sirve para
#                probar y para actualizar equipos cercanos sin tocar la nube.
#   --github     sube los artefactos y el manifiesto a una Release de GitHub
#                (`gh release`, descargables sin autenticar) y actualiza el
#                documento Firestore `app_config/release`. Es el canal público
#                recomendado.
#   --upload     sube los mismos archivos a Firebase Storage y actualiza el
#                documento Firestore `app_config/release`.
#
# Uso:
#   tool/publish_release.sh 2.0.1
#   tool/publish_release.sh 2.0.1 --notes-file NOTAS.txt
#   tool/publish_release.sh 2.0.1 --github
#   tool/publish_release.sh 2.0.1 --upload
#   tool/publish_release.sh 2.0.1 --dry-run
#
# Variables de entorno útiles:
#   RELEASE_REPO       repositorio de GitHub (por defecto CesarHGlez13/inutil-music,
#                      el mismo `--dart-define=RELEASE_REPO` que compila la app)
#   FB_PROJECT         proyecto Firebase (por defecto inutil-music-app)
#   MIN_SUPPORTED      versión mínima soportada (kill switch). Por defecto la
#                      versión que se publica: las anteriores dejan de funcionar.
#   MANDATORY=0        desactiva la actualización forzosa (por defecto: forzosa)
#
# Requisitos para --upload/--github: un token OAuth con permisos de escritura en
# el proyecto, en la variable FIREBASE_ACCESS_TOKEN. Se obtiene con
#   firebase login
#   firebase auth:token --project inutil-music-app
# (el script intenta leer también el token cacheado por el CLI de Firebase).
set -euo pipefail

PROY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${FB_PROJECT:-inutil-music-app}"
BUCKET="${FB_BUCKET:-inutil-music-app.firebasestorage.app}"
RELEASE_REPO="${RELEASE_REPO:-CesarHGlez13/inutil-music}"
# Rama donde nace la etiqueta. `gh release create` sin `--target` usa el branch
# *default*, que en este repo es `main`: una rama espejo **huerfana** creada solo
# para que Actions descubra el workflow, sin el codigo fuente de la app. Sin
# este flag la etiqueta apuntaria a un arbol sin `lib/`, y quien clone el tag no
# veria el codigo del que salio el binario. Medido 2026-11-21: `git merge-base
# origin/main origin/master` esta vacio (0 antepasados en comun), main tiene 9
# commits y master 56, y `git diff --stat main..master` son 1051 archivos.
RELEASE_TARGET="${RELEASE_TARGET:-master}"
MIN_SUPPORTED="${MIN_SUPPORTED:-}"
MANDATORY="${MANDATORY:-1}"
LOCAL_DIR="${INUTIL_RELEASES_DIR:-$HOME/inutil-releases}"
STORAGE_PREFIX="releases"

VERSION="${1:-}"; shift || true
MODE="local"; DRY=0; NOTES_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --upload) MODE="upload" ;;
    --github) MODE="github" ;;
    --local) MODE="local" ;;
    --dry-run) DRY=1 ;;
    --notes-file) NOTES_FILE="$2"; shift ;;
    *) echo "opción desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$VERSION" ] || { echo "uso: tool/publish_release.sh <version> [--upload|--local] [--notes-file NOTAS] [--dry-run]" >&2; exit 2; }

# --- artefactos existentes ----------------------------------------------------
APK_DIR="${INUTIL_APK_DIR:-$PROY/build/app/outputs/flutter-apk}"
DIST_DIR="${INUTIL_DIST_DIR:-$PROY/dist}"
declare -A FILES=()          # clave -> ruta
declare -A ABI_OF_KEY=()     # clave -> ABI legible
add_artifact() { # clave ruta abi
  [ -f "$2" ] || return 0
  FILES["$1"]="$2"
  ABI_OF_KEY["$1"]="${3:-}"
}
add_artifact universal      "$APK_DIR/app-universal-release.apk"               "universal"
add_artifact arm64_v8a      "$APK_DIR/app-arm64-v8a-release.apk"               "arm64_v8a"
add_artifact armeabi_v7a    "$APK_DIR/app-armeabi-v7a-release.apk"             "armeabi_v7a"
add_artifact x86_64         "$APK_DIR/app-x86_64-release.apk"                  "x86_64"
add_artifact linux          "$DIST_DIR/inutil_music_linux_x64.tar.gz"          ""
add_artifact linux          "$DIST_DIR/Inutil.Music-Linux-x86_64.AppImage"     ""
add_artifact linux_deb      "$DIST_DIR/InutilMusic-$VERSION-linux-amd64.deb"   ""
add_artifact linux_rpm      "$DIST_DIR/InutilMusic-$VERSION-linux-x86_64.rpm"  ""
add_artifact windows        "$DIST_DIR/InutilMusic-$VERSION-Windows-x64-Setup.exe" ""
add_artifact macos_arm64    "$DIST_DIR/InutilMusic-$VERSION-macOS-arm64.pkg"   ""
add_artifact macos_x64      "$DIST_DIR/InutilMusic-$VERSION-macOS-x64.pkg"     ""

# El AppImage reemplaza al tar.gz como paquete Linux recomendado.
APPIMAGE="$DIST_DIR/Inutil.Music-Linux-x86_64.AppImage"
TARGZ="$DIST_DIR/inutil_music_linux_x64.tar.gz"
if [ -f "$APPIMAGE" ] && [ -f "$TARGZ" ]; then
  FILES[linux]="$APPIMAGE"
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo "no hay artefactos construidos (buscados en $APK_DIR y $DIST_DIR)" >&2
  exit 3
fi

# --- notas de la versión ------------------------------------------------------
if [ -z "$NOTES_FILE" ] && [ -f "$PROY/CHANGELOG.md" ]; then
  NOTES_FILE="$PROY/CHANGELOG.md"
fi
NOTES_JSON='[]'
if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
  NOTES_JSON="$(VERSION="$VERSION" CHANGELOG="$NOTES_FILE" python3 - <<'PY'
import json, os, re

version = os.environ["VERSION"]
raw = open(os.environ["CHANGELOG"], encoding="utf-8", errors="replace").read()
lines = raw.splitlines()

# Sección del CHANGELOG que coincida con la versión (o la primera, si no está).
start = None
for i, line in enumerate(lines):
    if re.match(r"^#{1,3}\s*\[?" + re.escape(version) + r"\b", line):
        start = i + 1
        break
if start is None:
    for i, line in enumerate(lines):
        if re.match(r"^#{1,3}\s+\S", line):
            start = i + 1
            break
end = len(lines)
if start is not None:
    for j in range(start, len(lines)):
        if re.match(r"^#{1,3}\s+\S", lines[j]):
            end = j
            break

notes = []
lines = raw.splitlines()

# Secciones de nivel 2 ("## 1.3.1+131 — 2026-11-12" o "## Unreleased").
section_starts = [i for i, line in enumerate(lines) if re.match(r"^##\s+", line)]
chosen = None
for i in section_starts:
    if re.match(r"^##\s*\[?" + re.escape(version) + r"\b", lines[i]):
        chosen = i
        break
if chosen is None and section_starts:
    chosen = section_starts[0]

if chosen is not None:
    limit = len(lines)
    for j in section_starts:
        if j > chosen:
            limit = j
            break
    for line in lines[chosen + 1:limit]:
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        is_bullet = bool(re.match(r"^[-*]\s+", text))
        text = re.sub(r"^[-*]\s+", "", text)
        text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
        text = re.sub(r"`(.+?)`", r"\1", text)
        if not text or re.fullmatch(r"[-*]+", text):
            continue
        # El CHANGELOG va con envolturas duras: las líneas que no empiezan por
        # "-" continúan la viñeta anterior.
        if is_bullet or not notes:
            notes.append(text)
        else:
            notes[-1] = (notes[-1] + " " + text).strip()
        if len(notes) >= 12:
            break

if not notes:
    notes = ["Mejoras de rendimiento y estabilidad."]
print(json.dumps(notes, ensure_ascii=False))
PY
)"
fi

# --- manifiesto ---------------------------------------------------------------
MANIFEST_DIR="$(mktemp -d)"
MANIFEST="$MANIFEST_DIR/release.json"

# Lista clave<TAB>ruta<TAB>abi (orden estable, sin depender del orden de
# iteración de los arrays asociativos de bash).
ARTIFACTS_LIST="$MANIFEST_DIR/artifacts.tsv"
: > "$ARTIFACTS_LIST"
for key in $(printf '%s\n' "${!FILES[@]}" | sort); do
  printf '%s\t%s\t%s\n' "$key" "${FILES[$key]}" "${ABI_OF_KEY[$key]:-}" >> "$ARTIFACTS_LIST"
done

printf '%s' "$NOTES_JSON" > "$MANIFEST_DIR/notes.json"

MANIFEST="$MANIFEST" MANIFEST_DIR="$MANIFEST_DIR" ARTIFACTS="$ARTIFACTS_LIST" \
  VERSION="$VERSION" MODE="$MODE" BUCKET="$BUCKET" PREFIX="$STORAGE_PREFIX" \
  REPO="$RELEASE_REPO" MIN_SUPPORTED="$MIN_SUPPORTED" MANDATORY="$MANDATORY" \
  python3 - <<'PY'
import datetime, hashlib, json, os, pathlib

manifest_path = pathlib.Path(os.environ["MANIFEST"])
manifest_dir = pathlib.Path(os.environ["MANIFEST_DIR"])
version = os.environ["VERSION"]
bucket = os.environ["BUCKET"]
prefix = os.environ["PREFIX"]
mode = os.environ["MODE"]
repo = os.environ["REPO"]
min_supported = os.environ.get("MIN_SUPPORTED", "").strip() or version
mandatory = os.environ.get("MANDATORY", "1").strip() not in ("0", "false", "no")

notes_path = manifest_dir / "notes.json"
notes = json.loads(notes_path.read_text()) if notes_path.exists() else []

artifacts = []
for line in (manifest_dir / "artifacts.tsv").read_text().splitlines():
    if not line.strip():
        continue
    parts = line.split("\t")
    key, path = parts[0], parts[1]
    abi = parts[2] if len(parts) > 2 else ""
    if os.path.exists(path):
        artifacts.append((key, path, abi))


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


downloads = {}
sizes = {}
checksums = {}
linux_url = ""
linux_deb_url = ""
linux_rpm_url = ""
windows_url = ""
macos_arm64_url = ""
macos_x64_url = ""
for key, path, abi in artifacts:
    name = os.path.basename(path)
    size = os.path.getsize(path)
    checksums[name] = sha256(path)
    url = (
        "https://firebasestorage.googleapis.com/v0/b/" + bucket + "/o/" +
        prefix + "%2F" + name + "?alt=media"
    ) if mode == "upload" else (
        "https://github.com/" + repo + "/releases/download/v" + version + "/" + name
    ) if mode == "github" else "/api/releases/" + name
    if key == "linux":
        linux_url = url
    elif key == "linux_deb":
        linux_deb_url = url
    elif key == "linux_rpm":
        linux_rpm_url = url
    elif key == "windows":
        windows_url = url
    elif key == "macos_arm64":
        macos_arm64_url = url
    elif key == "macos_x64":
        macos_x64_url = url
    else:
        downloads[key] = url
        sizes[key] = size
        if abi:
            downloads[abi] = url
            sizes[abi] = size

manifest = {
    "schemaVersion": 1,
    "latestVersion": version,
    "minSupportedVersion": min_supported,
    "mandatory": mandatory,
    "publishedAt": datetime.datetime.now(datetime.timezone.utc)
    .isoformat(timespec="seconds"),
    "apkDownloadUrl": downloads.get("universal") or downloads.get("arm64_v8a") or "",
    "linuxDownloadUrl": linux_url,
    "linuxDebDownloadUrl": linux_deb_url,
    "linuxRpmDownloadUrl": linux_rpm_url,
    "windowsDownloadUrl": windows_url,
    "macosDownloadUrl": macos_arm64_url or macos_x64_url,
    "macosArm64DownloadUrl": macos_arm64_url,
    "macosX64DownloadUrl": macos_x64_url,
    "androidDownloads": downloads,
    "androidDownloadSizes": sizes,
    "packageSizeBytes": sizes.get("arm64_v8a") or sizes.get("universal") or 0,
    "releaseNotes": notes or ["Mejoras de rendimiento y estabilidad."],
    "checksums": checksums,
}

manifest_path.write_text(json.dumps(manifest, ensure_ascii=True, indent=2) + "\n")
print(
    "artefactos: "
    + ", ".join(os.path.basename(path) for _, path, _ in artifacts)
)
PY

echo "=== release.json ==="
cat "$MANIFEST"

if [ "$DRY" = "1" ]; then
  echo "(dry-run: no se subió ni se copió nada)"
  exit 0
fi

if [ "$MODE" = "local" ]; then
  mkdir -p "$LOCAL_DIR"
  for key in "${!FILES[@]}"; do
    cp -f "${FILES[$key]}" "$LOCAL_DIR/"
    echo "copiado: $LOCAL_DIR/$(basename "${FILES[$key]}")"
  done
  cp -f "$MANIFEST" "$LOCAL_DIR/release.json"
  echo "manifiesto: $LOCAL_DIR/release.json"
  echo "La app de la red local lo sirve en /api/release (mismo usuario)."
  exit 0
fi

# --- modo GitHub Release (canal público recomendado) --------------------------
if [ "$MODE" = "github" ]; then
  command -v gh >/dev/null 2>&1 || {
    echo "falta la CLI gh (https://cli.github.com) para --github" >&2; exit 5; }
  TAG="v$VERSION"
  NOTES_MD="$MANIFEST_DIR/notas.md"
  python3 - "$MANIFEST" "$NOTES_MD" <<'PY'
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
lines = [f"# Inútil Music {m['latestVersion']}", ""]
lines += [f"- {n}" for n in m.get("releaseNotes", [])]
if m.get("mandatory", False):
    lines += ["", "Actualización obligatoria: las versiones anteriores a "
              f"{m.get('minSupportedVersion', m['latestVersion'])} dejan de funcionar.", ""]
else:
    lines += ["", "Actualización opcional (versión mínima soportada: "
              f"{m.get('minSupportedVersion', m['latestVersion'])}).", ""]
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
  FILES_ARGS=()
  for key in "${!FILES[@]}"; do FILES_ARGS+=("${FILES[$key]}"); done
  FILES_ARGS+=("$MANIFEST")
  if gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "${FILES_ARGS[@]}" --clobber --repo "$RELEASE_REPO"
    echo "  la etiqueta $TAG ya existe; se suben los assets sin moverla"
  else
    gh release create "$TAG" "${FILES_ARGS[@]}" --repo "$RELEASE_REPO" \
      --target "$RELEASE_TARGET" \
      --title "Inútil Music $TAG" --notes-file "$NOTES_MD"
    echo "  etiqueta $TAG anclada en $RELEASE_TARGET (no en el branch default)"
  fi
  echo "publicado en https://github.com/$RELEASE_REPO/releases/tag/$TAG"
fi

TOKEN="${FIREBASE_ACCESS_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "$HOME/.config/configstore/firebase-tools.json" ]; then
  TOKEN="$(python3 - <<'PY'
import json, os, pathlib, time
p = pathlib.Path.home() / ".config" / "configstore" / "firebase-tools.json"
try:
    data = json.loads(p.read_text())
    tok = data.get("tokens") or {}
    # El CLI guarda el OAuth access token en `tokens.access_token` (con
    # `expires_at` en milisegundos). `tokens.user` no existe: leerlo devolvía
    # cadena vacía y el script se saltaba app_config/release en Firestore.
    access = tok.get("access_token", "") or ""
    exp = tok.get("expires_at", 0)
    if access and int(exp or 0) / 1000 - time.time() > 60:
        print(access)
    else:
        print("")
except Exception:
    print("")
PY
)"
fi
if [ -z "$TOKEN" ]; then
  if [ "$MODE" = "upload" ]; then
    echo "falta FIREBASE_ACCESS_TOKEN (firebase auth:token --project $PROJECT_ID)" >&2
    exit 4
  fi
  echo "aviso: sin FIREBASE_ACCESS_TOKEN; se omite app_config/release en Firestore" >&2
fi

upload() { # ruta local nombre tipo-contenido
  local src="$1" name="$2" ctype="$3"
  local meta
  meta="$(sha256sum "$src" | awk '{print $1}')"
  echo "subiendo $name ..."
  curl -sf --retry 3 --upload-file "$src" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: $ctype" \
    -H "X-Goog-Meta-Sha256: $meta" \
    -H "x-goog-meta-version: $VERSION" \
    "https://storage.googleapis.com/upload/storage/v1/b/$BUCKET/o?uploadType=media&name=$STORAGE_PREFIX%2F$name" \
    > /dev/null
  echo "  ok: $STORAGE_PREFIX/$name"
}

if [ "$MODE" = "upload" ]; then
  for key in "${!FILES[@]}"; do
    path="${FILES[$key]}"
    name="$(basename "$path")"
    case "$name" in
      *.apk) ctype="application/vnd.android.package-archive" ;;
      *.AppImage|*.tar.gz) ctype="application/gzip" ;;
      *.deb) ctype="application/vnd.debian.binary-package" ;;
      *.rpm) ctype="application/x-rpm" ;;
      *.exe) ctype="application/vnd.microsoft.portable-executable" ;;
      *.pkg) ctype="application/octet-stream" ;;
      *) ctype="application/octet-stream" ;;
    esac
    upload "$path" "$name" "$ctype"
  done

  upload "$MANIFEST" "release.json" "application/json; charset=utf-8"
fi

# --- sincronizar el documento Firestore que leen las apps ya instaladas -------
FIRESTORE_URL="https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/app_config/release"
BODY_FILE="$MANIFEST_DIR/firestore_body.json"
MANIFEST="$MANIFEST" python3 - <<'PY' > "$BODY_FILE"
import json, os
release = json.loads(open(os.environ["MANIFEST"], encoding="utf-8").read())
fields = {
    "latestVersion": {"stringValue": release["latestVersion"]},
    "minSupportedVersion": {
        "stringValue": release.get("minSupportedVersion", release["latestVersion"])
    },
    "apkDownloadUrl": {"stringValue": release.get("apkDownloadUrl", "")},
    "linuxDownloadUrl": {"stringValue": release.get("linuxDownloadUrl", "")},
    "linuxDebDownloadUrl": {"stringValue": release.get("linuxDebDownloadUrl") or "https://github.com/CesarHGlez13/inutil-music/releases/download/v2.5.15/InutilMusic-2.5.15-linux-amd64.deb"},
    "linuxRpmDownloadUrl": {"stringValue": release.get("linuxRpmDownloadUrl") or "https://github.com/CesarHGlez13/inutil-music/releases/download/v2.5.15/InutilMusic-2.5.15-linux-x86_64.rpm"},
    "windowsDownloadUrl": {"stringValue": release.get("windowsDownloadUrl") or "https://github.com/CesarHGlez13/inutil-music/releases/download/v2.5.15/InutilMusic-2.5.15-Windows-x64-Setup.exe"},
    "macosDownloadUrl": {"stringValue": release.get("macosDownloadUrl") or "https://github.com/CesarHGlez13/inutil-music/releases/download/v2.5.15/InutilMusic-2.5.15-macOS-arm64.pkg"},
    "macosArm64DownloadUrl": {"stringValue": release.get("macosArm64DownloadUrl") or "https://github.com/CesarHGlez13/inutil-music/releases/download/v2.5.15/InutilMusic-2.5.15-macOS-arm64.pkg"},
    "macosX64DownloadUrl": {"stringValue": release.get("macosX64DownloadUrl") or "https://github.com/CesarHGlez13/inutil-music/releases/download/v2.5.15/InutilMusic-2.5.15-macOS-x64.pkg"},
    "mandatory": {"booleanValue": bool(release.get("mandatory", False))},
    "publishedAt": {"timestampValue": release["publishedAt"]},
    "releaseNotes": {"arrayValue": {"values": [{"stringValue": n} for n in release.get("releaseNotes", [])]}},
    "packageSizeBytes": {"integerValue": str(int(release.get("packageSizeBytes", 0)))},
    "androidDownloads": {
        "mapValue": {"fields": {k: {"stringValue": v} for k, v in release.get("androidDownloads", {}).items()}}
    },
}
print(json.dumps({"fields": fields}, ensure_ascii=False))
PY

if [ -n "$TOKEN" ]; then
  echo "actualizando Firestore app_config/release ..."
  curl -sf -X PATCH "$FIRESTORE_URL" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data @"$BODY_FILE" > /dev/null && echo "  ok: Firestore actualizado" || \
    echo "  AVISO: no se pudo actualizar Firestore (¿Auth/Storage habilitado o token sin permisos?)" >&2
fi

echo "publicado v$VERSION"
