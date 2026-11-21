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
16. Gradle: el job `quality` **no puede** usar el `gradle` que trae el runner ni
    un `gradle-version` al azar, y tampoco puede invocar `./gradlew` antes de
    `flutter build apk`. Medido en dos runs seguidos (`44879291272` y
    `44891202761`): con `gradle-version: "8.14.3"` el paso de pruebas unitarias
    reventó con `Minimum supported Gradle version is 9.3.1. Current version is
    8.14.3` (la exigencia la pone AGP `com.android.application` **9.1.1** en
    `android/settings.gradle.kts:23`); al cambiarlo a `./gradlew` reventó con
    `./gradlew: No such file or directory` exit 127, porque `android/.gitignore:4`
    ignora `/gradlew` (y `:1` ignora `gradle-wrapper.jar`), así que en CI el
    checkout **no trae** wrapper: Flutter lo inyecta desde su caché
    (`gradle_utils.dart:229-246`, `getExecutable` → `injectGradleWrapperIfNeeded`)
    sólo cuando corres `flutter build apk`, y `flutter test` no lo crea. Por eso
    el workflow ahora instala `gradle-version: "9.5.0"` — el mismo
    `distributionUrl` de `android/gradle/wrapper/gradle-wrapper.properties` — y
    un paso `Assert Gradle matches the Android wrapper` compara las dos versiones
    y exige `>= 9.3.1`; si alguien sube el wrapper sin subir el pin, el gate lo
    ve. Verificado en local con las dos variantes (`PATH` con un `gradle` 9.5.0
    → el paso pasa; con uno 8.14.3 → rc 1) y las pruebas unitarias con Gradle
    9.5.0: `BUILD SUCCESSFUL in 18s` con la
    misma forma que usará CI (`cd android`, `gradle` 9.5.0 en PATH,
    `--no-daemon`), tras forzar la re-ejecución con
    `:app:cleanTestDebugUnitTest :just_audio:cleanTestDebugUnitTest` (BUILD
    SUCCESSFUL in 16s, 6 actionable tasks: 2 ejecutados): 326 actionable tasks:
    3 ejecutados, 323 up-to-date, y los 4 XML tallyados con ElementTree dan
    16 + 4 + 3 + 3 = **26 pruebas, 0 failures, 0 errors, 0 skipped**. Si el
    launcher de Gradle sobrevive a `BUILD SUCCESSFUL`, no le eches la culpa a
    Gradle: medido, `STAT=T` y `wchan=do_signal_stop` (`State: T (stopped)`), y
    corrido con `setsid` sale `RC=0 ELAPSED=27s` sin dejar procesos — es un
    sandbox deteniendo el grupo de procesos de una tarea mandada a segundo
    plano. En CI el job corre en primer plano y `setup-gradle` detiene sus
    daemons al final, así que `--no-daemon` se queda.
    OJO con el `sed` que lee las versiones: `s/^Gradle \([0-9.]*\)$/1/p`
    devuelve el literal `1` (no `\1`) y el control se vuelve tonto; hay que
    escribir `sed -nE 's/^Gradle ([0-9.]+)$/\1/p'`.
17. El pub cache **no es parte del repo**, así que cualquier arreglo que viva
    ahí produce la trampa «aquí compila, en CI no». Medido con
    `flutter_inappwebview_android-1.1.3`: el `android/build.gradle` que publica
    pub.dev (tarball `sha256 62557c15a5c2db5d195cb3892aab74fcaec266d7b86d59a6f0027abd672cddba`,
    igual al `sha256` de `pubspec.lock`) llama
    `getDefaultProguardFile('proguard-android.txt')` en las líneas 44 y 48, y
    AGP 9.1.1 (`android/settings.gradle.kts:23`) lo rechaza porque
    `proguard-android.txt` incluye `-dontoptimize`. La copia local del pub cache
    estaba parcheada a `proguard-android-optimize.txt` (+18 bytes, sólo esas dos
    líneas; mtime 14:43 vs 14:08 de sus hermanos), así que en mi máquina todo
    salía verde y en CI no. Control A/B, con la misma forma que usará CI
    (`cd android`, Gradle 9.5.0 en PATH, `--no-daemon`):
    * pristino → `BUILD FAILED in 20s`, `A problem occurred evaluating project
      ':flutter_inappwebview_android'`, `Build file '...build.gradle' line: 44`,
      `> getDefaultProguardFile('proguard-android.txt') is no longer supported`
      (idéntico al run `44895843926`, que en CI tardó `BUILD FAILED in 2m 42s`
      porque el cache estaba frío).
    * parcheado → `BUILD SUCCESSFUL in 17s` (`RC=0 ELAPSED=19s`), y tras forzar
      la re-ejecución con `:app:cleanTestDebugUnitTest
      :just_audio:cleanTestDebugUnitTest` (`CLEAN_RC=0`, 6 actionable tasks: 2
      ejecutados): `BUILD SUCCESSFUL in 18s`, 326 actionable tasks: 3 ejecutados,
      323 up-to-date, con los 4 XML regenerados → 16 + 4 + 3 + 3 = **26 pruebas,
      0 failures, 0 errors, 0 skipped**.
    El arreglo vive en `tool/patch_pub_cache_proguard.sh` y el workflow lo invoca
    como paso `Patch pub-cache plugins for AGP 9` en los dos jobs que tocan
    Gradle (`Required quality gate`, posición 6 de 15, y `Android release APKs`,
    posición 6 de 12, antes de `Build ARMv7…`, que jamás llegó a correr porque el
    gate reventaba y lo dejaba `skipped`). El script es idempotente —la segunda
    corrida reporta `0 archivo(s) parcheados, 0 restantes`— y sale con exit 1 si
    queda algún `.txt`, así que no se cuela un plugin nuevo sin que el gate lo
    vea. Si upstream migra a `proguard-android-optimize.txt`, el script deja de
    parchear solos y se puede quitar.
18. La trampa de las llaves simples en el workflow: `--dart-define=FB_RELAY_HOST=${ env.FB_RELAY_HOST }`.
    GitHub Actions solo expande `${{ ... }}`; con una sola llave el texto llega
    VERBATIM al shell y bash lo interpreta como `${ env.X }`, que es
    `bad substitution`. En el run `44897842893` eso tumbó los jobs `Linux x64
    installers`, `macOS`, `iOS` y el build de Windows con `##[error]Process
    completed with exit code 1` y una línea `\.sh: line 1: --dart-define=FB_RELA`
    (el shell intentó ejecutar el `--dart-define` porque la expansión se llevó
    el resto). Fueron 10 ocurrencias repartidas en 4 jobs, y las tres líneas de
    cada job se escribieron juntas porque el bloque se generó con un
    `format()` de Python donde `{{`/`}}` colapsaron a `{`/`}` — es decir: el
    propio arreglo del `env:` anterior se comió una llave. Arreglado con
    `sed -E 's/\$\{ env\.([A-Za-z_]+) /${{ env.\1 /g'`; controles medidos
    después: `grep -c '${ env.'` = **0**, `grep -c '${{ env.'` = **34**,
    `python3 -c 'import yaml; yaml.safe_load(open(...))'` = OK, y en los 6 pasos
    de `flutter build` el log ahora imprime los dos `--dart-define` con los
    hosts horneados. Lección: ante un `exit 1` en un paso de `run: >-`, lo
    primero es `gh run view --log` y mirar cómo el runner ECHOEÓ el comando,
    no solo el pie del error.
19. `Test Windows animated artwork` en verde, y por qué se cayó 5 pruebas.
    El paso arrancó en `44897842893` con **19 passed / 5 failed / 2 skipped**
    (`test/features/music/presentation/widgets/player_canvas_layout_test.dart`
    entre los 9 archivos). Las 5 fallas eran tres cosas distintas:
    * **`ProviderException: A InutilPlaybackSyncService was used after being
      disposed`** en `_SpotifyFullscreenCanvasPlayer.build`. El servicio de
      sincronización es un singleton global y el primer `ProviderContainer` de
      cada prueba lo DESMONTABA: `ChangeNotifierProvider` de riverpod 3.4.3
      llama `value.dispose()` al cerrar el contenedor porque `disposeNotifier`
      vale `true` por defecto (`…/flutter_riverpod-3.4.3/lib/src/providers/
      legacy/change_notifier_provider.dart:248` lo salta si vale `false`).
      Probado con una prueba sonda: contenedor default → `sawDispose=true` y
      el siguiente `addListener` lanza `Bad state: A Probe was used after being
      disposed`; con `disposeNotifier: false` → `sawDispose=false` y
      `addListener` responde `Null: null` sin lanzar. Arreglo de producto:
      `disposeNotifier: false` en `inutilAuthProvider` y
      `inutilPlaybackSyncProvider` (`lib/core/firebase/
      firebase_sync_providers.dart`), que comparten el objeto entre contenedores
      y entre la app y las pruebas, más la prueba permanente
      `test/core/firebase/shared_singleton_dispose_test.dart`.
    * **Expectaciones de `Rect` viejas**: el test nació antes del modo
      "canvas a pantalla completa" y seguía esperando que el vídeo se recortara
      encima de la carátula. Medido en retrato ancho (800x1200): carátula
      `164,404,636,876`, vídeo `0,0,800,1200` y `canvasmode=1`; en
      `appleMusic` el vídeo coincide con la carátula y `canvasmode=0`. Ahora el
      test deriva `canvasFullscreen` con la misma regla que
      `player_panel.dart:626` (`canUseSpotifyFullscreenCanvas`) y exige
      `player-canvas-viewport` == pantalla entera.
    * **Regla de píxeles inalcansable por diseño**: el
      `SpotifyFullscreenCanvasPlayer` pinta su propio scrim de legibilidad
      (`spotify_fullscreen_canvas_player.dart:181`, LinearGradient con stops
      `[0, .16, .36, .58, .78, 1]` y alphas de negro
      `[.62, .14, 0, .52, .90, .96]`). Interpolado: α=.933 en yf=.9, .946 en
      .95, .953 en .975, .957 en .99, .96 en el borde, o sea que del 90 % de la
      pantalla al borde físico solo sobrevive el 4 %-7 % de la señal del lienzo.
      Perfil medido (con/lienzo contra sin/lienzo, x=.5, 390x820):
      dy 738 → [18,37,36], 656 → [47,47,61], 164 → [116,127,112],
      123 → [52,44,57], 82 → [27,17,31], 41 → [12,2,16], 20.5 → [12,2,16],
      8.2 → [28,16,31], 2.0/1.0 → [27,16,31] (spotifyMusic igual, 10/1/14 en
      las filas del pill de controles). Por eso exigir `delta > 32` en las dos
      últimas filas era imposible por principio: se muestrea la VENTANA CLARA
      del scrim (yf .16/.26/.36/.4, donde α vale .14 → 0) y "el lienzo llega al
      borde" lo garante el assert geométrico, no el píxel.
      Se le sumó el drenado de reloj: el buscador de letras que monta el modo a
      pantalla completa deja un temporizador que caduca a los **6.998 s** y
      `flutter_test` exige `!timersPending`, y `_fullscreenCanvasGraceDuration`
      = 1400 ms (`player_panel.dart:244`) retiene el `SpotifyCanvasVideo` después
      de apagar el canvas, así que hay que `pump(1600 ms)` antes de exigir que
      ya no esté.
    Receta para ver esto en Linux sin Windows: `player_panel.dart:407` excluye
    `AppPlatformType.linux` de `remoteArtworkAllowed` (el canvas remoto está
    cortado en Linux por diseño), y `AppPlatform` se basa en `Platform.isWindows`
    real, así que no se puede fingir en una prueba. Lo que sí funciona: parchar
    temporalmente esa línea 407 a `true &&` + `skip: false` en los dos bucles,
    y entonces el archivo reproduce EXACTAMENTE lo de Windows (medido: `+19 -5`
    con los mismos 5 nombres y `disposed count = 0` después del arreglo). Con
    ese parche el archivo quedó **24 passed / 0 failed** (`PROBE9_RC=0`);
    revertido el parche, el subconjunto de los 9 archivos vuelve a su estado
    sano en Linux y el `skip` documentado hace que las 24 pruebas de canvas se
    salten aquí y se ejecuten en los runners de Windows/macOS.
