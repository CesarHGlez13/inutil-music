# Publicar una versión de Inútil Music (OTA)

1. Sube la versión en `pubspec.yaml` (`version: 2.0.1+201`) y en
   `lib/core/constants/app_constants.dart` (`appVersion = '2.0.1'`).
2. Escribe las novedades en `CHANGELOG.md` bajo un encabezado `## 2.0.1`.
3. `flutter build apk --release --split-per-abi` (el flag es `--split-per-abi`, no `--split-abi`).
   Con este flag Flutter suma un desplazamiento de ABI al `versionCode`.
   Medido con `aapt` (build-tools 36.0.0) sobre Flutter 3.50 usando
   `2.5.10+4268`: `6268` (arm64-v8a), `5268` (armeabi-v7a) y `8268` (x86_64),
   o sea desplazamientos `+2000`, `+1000` y `+4000`. La documentación anterior
   prometía `2210` para arm64 con `2.1.0+210` (`+1000`): ese desplazamiento subió
   a `+2000` en Flutter moderno, así que un teléfono con `6267` instalado acepta
   sin rechazar por downgrade un `6268` (`+4268`) o un `6269` (`+4269`). Ignora
   `app-release.apk` si no se reconstruyó: puede seguir siendo de una versión
   anterior (medido: el `app-release.apk` del árbol era `1.3.1+131`).
4. `flutter build linux --release && bash tool/package_linux.sh` → `dist/inutil_music_linux_x64.tar.gz`.
5. `bash tool/publish_release.sh 2.0.1 --dry-run` → revisa el `release.json` impreso.
6. Prueba local: `bash tool/publish_release.sh 2.0.1` deja APK + tar.gz + `release.json`
   en `~/inutil-releases/`; el PC los sirve en `/api/release` y `/api/releases/<archivo>`.
7. Auto-update de Linux: `bash tool/test_update_swap.sh` → `RESULTADO: PRUEBA
   SUPERADA` (reemplanta `data/` y `lib/`, relanza y limpia el staging).
8. Canal público (recomendado hoy): `FIREBASE_ACCESS_TOKEN=… bash tool/publish_release.sh 2.0.1 --github`
   → Release `v2.0.1` de `CesarHGlez13/inutil-music` (assets descargables sin sesión)
   + `PATCH` de `app_config/release`. El token sale del `refresh_token` del CLI de
   Firebase y caduca a la hora.
9. Alternativa `--upload` (Cloud Storage): sigue bloqueada hasta aprovisionar
   Storage en la consola. Medido el 2026-11-17 con `firebase deploy --only storage:rules`:
   *«Firebase Storage has not been set up on project 'inutil-music-app' … click
   'Get Started'»*. El bucket por defecto del script es
   `inutil-music-app.firebasestorage.app` (el nombre `inutil-music-7b1fa` que
   aparecía en la documentación no existe).
10. Reglas: tras cualquier cambio en `firebase/firestore.rules` hay que
    `firebase deploy --only firestore:rules --project inutil-music-app`; sin ese
    paso la lectura anónima de `app_config/release` da 403 y el kill switch nunca
    se entera de la versión nueva (los tests del emulador no lo detectan porque el
    emulador carga las reglas locales).
11. Desde `2.5.11+4269` la app **avisa sola**: `InutilUpdateGate` ya consultaba el
    manifiesto al arrancar y al volver de segundo plano (cooldown 5 min), pero
    antes sólo pintaba algo si `belowMinSupported` o si el manifiesto venía
    `mandatory:true`; ahora, con una versión superior opcional, muestra el
    diálogo de novedades como cartel descartable y al cerrarlo guarda la versión
    pospuesta en `inutil_update_notice_snoozed_for`, así que no vuelve a molestar
    hasta publicar algo superior. Verificación manual sigue igual: Ajustes →
    Actualizaciones → «Buscar actualizaciones» → debe salir la versión nueva con
    su tamaño y sus notas.
12. Detalle completo (esquema del manifiesto, reglas de Firestore, reanudación
    de la descarga e instalación en Android): sección «Publicar una nueva
    versión (OTA)» de `README.md`.

13. Instalación real en Android: `InutilUpdateService.downloadUpdate` baja el APK
    a `Directory.systemTemp` y lo abre con `url_launcher`
    (`launchUrl(Uri.file(…))`), así que es el sistema (PackageInstaller) quien
    muestra el instalador y el usuario confirma; no existe instalación silenciosa
    ni permiso `REQUEST_INSTALL_PACKAGES` propio. Las clases
    `AndroidPackageInstaller`, `OtaDownloadManager` y `OtaPlaybackResumeStore`
    de `lib/services/app_update/` están definidas pero no se instancian en ningún
    punto de `lib/` (medido con `grep -rn` sobre `lib/**/*.dart`), así que no
    forman parte del camino que se ejecuta al actualizar. En Linux sí hay
    self-install completo: `_installLinuxArchiveAndRelaunch` prepara un staging,
    lanza un script desacoplado que espera a que muera el proceso, reemplanta
    `data/` y `lib/` en `~/.local/share/inutil-music` y relanza la app
    (`bash tool/test_update_swap.sh` → `RESULTADO: PRUEBA SUPERADA`).
