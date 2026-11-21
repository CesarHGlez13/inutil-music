#!/usr/bin/env bash
# Compatibilidad AGP 9.1.1: `getDefaultProguardFile('proguard-android.txt')` ya
# NO es válido (AGP 9 lo rechaza porque `proguard-android.txt` incluye
# `-dontoptimize`), y el error ocurre al EVALUAR el `build.gradle` del plugin,
# así que no se puede corregir después: hay que parchear el archivo antes de
# que Gradle lo lea. Medido: con el archivo pristino de pub.dev
# `flutter_inappwebview_android-1.1.3` (sha256 del tarball
# 62557c15a5c2db5d195cb3892aab74fcaec266d7b86d59a6f0027abd672cddba),
# `gradle :app:testDebugUnitTest :just_audio:testDebugUnitTest --no-daemon`
# sale `BUILD FAILED in 20s` / `A problem occurred evaluating project
# ':flutter_inappwebview_android'` / `Build file '...build.gradle' line: 44`;
# con la línea cambiada a `proguard-android-optimize.txt` la misma corrida
# vuelve a `BUILD SUCCESSFUL` con las 26 pruebas en verde.
#
# Por qué vive aquí y no en `android/build.gradle`: el archivo parcheado está
# en el pub cache (`$PUB_CACHE/hosted/pub.dev/...`), que NO es parte del repo,
# así que un arreglo local se convierte en la trampa "aquí sí compila, en CI
# no" — exactamente lo que pasó entre mi máquina y el run 44895843926. Este
# script es idempotente y termina en error si queda algún `.txt` sin parchear,
# así CI y las máquinas locales convergen al mismo estado.
set -uo pipefail

PUBCACHE="${PUB_CACHE:-$HOME/.pub-cache}"
if [ ! -d "$PUBCACHE/hosted/pub.dev" ]; then
  echo "no existe $PUBCACHE/hosted/pub.dev; corres 'flutter pub get' primero" >&2
  exit 1
fi

# AGP 9.1.1 (`android/settings.gradle.kts:23`) exige Gradle >= 9.3.1, y ese
# Gradle es el que vuelve error esta llamada; el texto de AGP manda usar
# `proguard-android-optimize.txt`.
PATTERN="getDefaultProguardFile('proguard-android\.txt')"
PATTERN2='getDefaultProguardFile("proguard-android\.txt")'

patched=0
while IFS= read -r -d '' f; do
  sed -i -e "s/getDefaultProguardFile('proguard-android\.txt')/getDefaultProguardFile('proguard-android-optimize.txt')/g" \
       -e 's/getDefaultProguardFile("proguard-android\.txt")/getDefaultProguardFile("proguard-android-optimize.txt")/g' \
       "$f"
  patched=$((patched + 1))
  echo "  parcheado: ${f#"$PUBCACHE"/hosted/pub.dev/}"
done < <(grep -rlZ --include='*.gradle' --include='*.gradle.kts' -e "$PATTERN" -e "$PATTERN2" \
  "$PUBCACHE/hosted/pub.dev" 2>/dev/null)

remaining=$(grep -rl --include='*.gradle' --include='*.gradle.kts' -e "$PATTERN" -e "$PATTERN2" \
  "$PUBCACHE/hosted/pub.dev" 2>/dev/null | wc -l | tr -d ' ')
if [ "$remaining" -ne 0 ]; then
  echo "quedan $remaining archivos con getDefaultProguardFile('proguard-android.txt')" >&2
  grep -rl --include='*.gradle' --include='*.gradle.kts' -e "$PATTERN" -e "$PATTERN2" \
    "$PUBCACHE/hosted/pub.dev" 2>/dev/null | head -10 >&2
  exit 1
fi
echo "ok: $patched archivo(s) parcheados, $remaining restantes (AGP 9.1.1 lo exige)"
