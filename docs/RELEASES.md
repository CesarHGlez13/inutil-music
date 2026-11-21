# Publicar una versión de Inútil Music (OTA)

1. Sube la versión en los **cinco** sitios que `test/core/constants/
   app_metadata_test.dart` compara entre sí (si uno se queda atrás, la prueba se
   cae): `pubspec.yaml` (`version: 2.0.1+201`),
   `lib/core/constants/app_constants.dart` (`appVersion = '2.0.1'`),
   `README.md` (`Current version: **2.0.1+201**`),
   `packaging/windows/InutilMusic.iss` (`#define MyAppVersion "2.0.1"`, de ahí
   sale el nombre `InutilMusic-2.0.1-Windows-x64-Setup.exe` que genera CI) y la
   aserción `expect(pubspecVersion, '2.0.1+201')` de esa misma prueba.
   OJO: `README.md` y `CHANGELOG.md` no son decorativos —el regex de la prueba
   toma el **primer** `## X.Y.Z+BUILD` del CHANGELOG, así que la sección nueva
   tiene que ir arriba (más nueva primero)—.
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

14. Kill switch (OTA forzosa): `tool/publish_release.sh` lee `MIN_SUPPORTED` y
    `MANDATORY` del entorno, y **por defecto `minSupportedVersion` es la versión
    que se publica** (`tool/publish_release.sh:29` y `:195-196`:
    `min_supported = … or version`, `mandatory = … not in ("0","false","no")`).
    Publicar `2.5.14` sin variables deja el manifiesto
    `latest=2.5.14 min=2.5.14 mandatory=true` y obliga a actualizar a quien esté
    por debajo. Medido el 2026-11-20 con `latest=2.5.13 min=2.5.13`: la lectura
    anónima de `app_config/release` responde `mandatory=True` en 0.27 s y **10**
    de las 12 identidades registradas en `users/{uid}/devices` quedan por debajo
    del mínimo. OJO con el orden: sube **primero** el binario y **después** el
    manifiesto, porque con el mínimo ya subido y sin descarga posible la pantalla
    obligatoria deja atascada a la gente (el `HEAD` del APK publicado debe
    responder `200` con `content-type=application/vnd.android.package-archive`).
15. Los servidores tienen que ir **horneados en el binario**:
    `.github/workflows/desktop-builds.yml` pasó a definir
    `FB_RELAY_HOST: "192.168.100.27"` y
    `FB_CLOUD_RELAY_HOST: "inutil-cloud-relay.scada-xiaomi-server.workers.dev"`
    en su bloque `env:` y los pasa como `--dart-define` a los **seis**
    `flutter build` (android, ios ×2, windows, linux, macos). Cada job lo
    comprueba sobre su propio artefacto **contando** coincidencias
    (`grep -a -c`), no preguntando "¿existe?" a secas: `unzip -p <apk>
    lib/<abi>/libapp.so | grep -a -c <host>` para Android, `grep -a -c <host>
    build/linux/x64/release/bundle/lib/libapp.so` para Linux (ruta verificada
    con `find build -name libapp.so`) y `grep -R -a -c` sobre el bundle para
    Windows/macOS. Por qué no `grep -a -q` dentro de la tubería: corta la
    entrada, `unzip` muere de SIGPIPE y con `set -o pipefail` —que esos steps
    sí llevan— la tubería devuelve **141 AUNQUE el host esté presente**, o sea
    un falso negativo que habría roto el gate. Medido: `grep -a -q` sobre el
    `.so` extraído rc 0; el mismo `grep -a -q` recibido por tubería rc 141;
    `grep -a -c` por tubería da el conteo (1) y rc 0. Medido sobre los binarios locales: **0**
    ocurrencias en el build sin defines y **1** de cada host en el build con
    ellos, así el control sí discrimina. Sin esos defines el binario habla solo
    con Google y ni el relay de la LAN ni el Worker cloud funcionan — así
    salieron los `v2.5.12` y `v2.5.13` publicados, que eran byte-idénticos a un
    build sin endpoints (`sha256 42a81121…`).
