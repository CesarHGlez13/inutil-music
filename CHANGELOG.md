# Changelog

## 2.5.21+4279 — 2026-11-23

### Improved — Adaptación del reproductor completo en laptop al estilo y proporciones del mini reproductor

- **Diseño adaptado para escritorio y laptop en Canvas a pantalla completa.**
  Se eliminó la restricción de ancho móvil (`maxWidth: 560px`) en pantallas de escritorio. La vista del reproductor a pantalla completa ahora aprovecha todo el espacio disponible sin compactar los controles ni forzar la interfaz vertical de teléfono.
- **Bandeja de controles estilo mini reproductor (cápsula liquidGlass).**
  La botonera y controles inferiores adoptan la estética del mini reproductor: cápsula translúcida flotante con desenfoque `liquidGlass` (radio de 40px), carátula de 60px con metadatos a la izquierda, controles de transporte completos y barra de tiempo en el centro, y accesos rápidos a letras, temporizador de sueño, cola, dispositivos y control deslizante de volumen a la derecha.
- **Letras sincronizadas centradas y eliminación de controles redundantes en escritorio.**
  La línea de letra sincronizada en vivo se centra en pantalla con tipografía optimizada (26px) sobre el Canvas de fondo. Se oculta el botón móvil de colapso hacia abajo (`v`) y la tarjeta inferior redundante de letras.

## 2.5.19+4277 — 2026-11-23

### Fixed — Canvas de video de artista y sincronización de letra restaurados (estilo v2.5.15)

- **Canvas de video del artista como fallback visual seguro.**
  Se restauró el comportamiento visual de la versión 2.5.15 donde canciones sin video individual propio en iTunes (como temas de álbum) aprovechan clips oficiales del mismo artista (`sameVisualArtist`) para animar el reproductor en pantalla completa y la vista de letra sincronizada, garantizando que nunca se muestren videos de otros artistas.
- **OTA opcional sin bloqueo forzado.**
  Corrección en el script de publicación para respetar el valor vacío de `MIN_SUPPORTED=""` sin forzar erróneamente un kill switch de versión mínima.

## 2.5.18+4276 — 2026-11-23

### Fixed — Fallback de Video Preview ampliado y Canvas resiliente

- **Fallback de Video Preview ampliado con validación estricta.**
  Se amplió la cobertura de búsqueda en iTunes/Apple Music mediante consultas escalonadas por título y catálogo de artista manteniendo validación estricta de título y artista (`sameVisualTitle` y `sameVisualArtist`) para no mostrar videos de canciones o artistas erróneos.
- **Soporte de identificadores de Canvas de proveedor.**
  Se aceptan identificadores de Canvas con prefijo `t_1.*` para resolver Canvas oficial en cuanto el servicio de proveedor se reanude.
- **Actualización opcional.**
  Actualización opcional: no hay versión mínima soportada (`minSupportedVersion ""` cancela la OTA obligatoria).

## 2.5.17+4275 — 2026-11-22

### Fixed — Resolución y reproducción exacta en Video Preview Reel

- **Corrección de reproducción exacta en carrusel de Video Preview.**
  Se corrigió el error en los perfiles de artistas y páginas de colecciones donde reproducir cualquier video clip del carrusel de vista previa mandaba siempre a la primera canción popular del artista. Ahora resuelve y busca dinámicamente la pista exacta en streaming para reproducir el tema seleccionado.
- **Actualización obligatoria.**
  Esta versión se publica como **actualización obligatoria** (`minSupportedVersion 2.5.17`).

## 2.5.16+4274 — 2026-11-22

### Improved — Android Auto Coolwalk con recomendaciones y Explorar, resolución de bucle OTA con verificación de firmas, Canvas cinemático y audio HQ pre-resuelto sin micro-cortes

- **Android Auto Coolwalk nativo y navegación completa estilo Spotify.**
  Integrado servicio `MediaBrowserService` con 4 pestañas principales: **Inicio** (combinando recomendaciones personalizadas, *Seguir escuchando*, *Tus playlists*, *Porque escuchaste...*, *Nuevos para ti*, *Descubrimiento*, *Artistas populares* y *Mixes* en cuadrícula HD 640×640), **Explorar** (catálogo completo por estados de ánimo y géneros con playlists y canciones), **Playlists** (tus listas guardadas) y **Biblioteca** (favoritos y pistas descargadas sin conexión). Controles personalizados en pantalla de auto: Favorito (`♡` ↔ `♥`), Aleatorio (`🔀`) y Repetir (`🔁`), cola completa de reproducción y compatibilidad total con pantalla dividida Google Maps (Coolwalk).
- **Corrección definitiva de bucle de actualización OTA y sincronización de versiones.**
  Se corrigió el bloqueo cíclico donde la app se exigía actualizarse repetidamente a sí misma (*«Versión 2.5.16 disponible · Tienes v2.5.15»*). Se alineó `AppConstants.appVersion` a `'2.5.16'`, sincronizándolo con `pubspec.yaml` y Firestore `minSupportedVersion`. Además se integraron validaciones automáticas de firma de producción (`inutilmusic.keystore`) y chequeo de integridad en el pipeline de publicación (`tool/publish_release.sh`).
- **Audio HQ pre-resuelto sin micro-cortes.**
  Pre-resolución asíncrona y en paralelo de flujos JioSaavn 320 kbps antes de iniciar la reproducción para arrancar directamente en alta fidelidad y eliminar micro-cortes causados por intercambios de reproductor en caliente. Calidad alta reactiva desactivada por defecto para máxima estabilidad.
- **Spotify Canvas cinemático y respaldo visual animado inteligente.**
  Validación estricta de título y artista para evitar clips incorrectos en canciones no identificadas; cuando no hay clip disponible se expande la carátula con efecto de movimiento cinemático Ken Burns y aura reactiva ambiental.
- **Actualización obligatoria.**
  Esta versión se publica como **actualización obligatoria** (`minSupportedVersion 2.5.16`).

## 2.5.15+4273 — 2026-11-21

### Improved — Spotify Connect sin congelamientos, Canvas a pantalla completa en escritorio/letras, motor Linux optimizado y OTA obligatoria multiplataforma

- **Selección desde Biblioteca y Spotify Connect sin congelamientos ni canciones fantasma.**
  Se corrigió el desfase de URL (`music.youtube.com` vs `www.youtube.com`) al transferir colas de playlists entre móvil y PC que abortaba la resolución como reemplazada y congelaba el altavoz en pausa con el tiempo anterior; también se evitó que un prefetch cancelado afectara la selección activa en `RemoteTrackResolver`, se protegió `_decorateSnapshot` frente a snapshots salientes, se eliminó la explosión de posición en `/api/session` sincronizando `updatedAt`, se evitó que equipos inactivos en LAN secuestraran el auto-emparejamiento y se alineó el resaltado de filas en `Biblioteca` con la pista real del altavoz remoto.
- **Canvas a pantalla completa en escritorio, en Letras y con respaldo visual inteligente.**
  En escritorio el reproductor con Canvas oculta la barra lateral y usa tema oscuro completo sin parpadeo; la pantalla de letras sincronizadas ahora muestra el fondo Canvas animado; y las canciones que no tienen video en Spotify Canvas mantienen el estilo Canvas con carátula animada nítida y fallback de video preview de YouTube/iTunes sin degradarse al reproductor clásico.
- **Motor nativo Linux Canvas optimizado (`InutilLinuxCanvasEngine`).**
  Se desactivó la salida de audio en el `mpv` del Canvas (`ao=null`), se eliminó la comprobación frágil de AOT y se ajustó el muestreo a 15 FPS / 320×568, reduciendo el consumo de CPU en Linux de ~72% a ~16% sin perder fluidez.
- **Ahorro de cuota en nube y panel de administración web mejorado.**
  Las cuentas con un solo equipo en línea ahora espacian el sondeo en la nube a 30 s (despertando al instante al detectar un segundo dispositivo) y el Cloudflare Cloud Relay amplió su caché de identidad a 55 min + RAM por isolate (reduciendo 11x las escrituras de KV). El panel de administración en `https://inutil-music-app.web.app` ya no cierra la sesión del admin al crear cuentas, incluye generador de contraseñas legibles, botón de WhatsApp en 1 clic, recuperación de contraseña y monitoreo del Cloud Relay.
- **Actualizaciones directas multiplataforma y firma de producción definitiva.**
  Windows y macOS (Apple Silicon e Intel) descargan su instalador nativo (`.exe` y `.pkg`), Linux prioriza su paquete propio (`.tar.gz`, `.deb` o `.rpm`) y los APKs de Android salen firmados con el certificado de producción propio válido hasta 2054. Se corrigió además `shaders/liquid_glass_refraction.frag` para compilar con 0 advertencias en todas las plataformas. Esta versión se publica como **actualización obligatoria** (`minSupportedVersion 2.5.15`).

## 2.5.14+4272 — 2026-11-20

### Fixed — la interfaz que César reportó en pantalla

- **El icono de recargar ya no es un garabayo asimétrico.** Se redibujó el
  glifo `InutilGlyph.refresh` como dos arcos punto-simétricos con dos puntas
  que llenan los cuatro cuadrantes dentro de la caja de 24 unidades; la
  rotación de 60°/120°/180° reproduce el mismo glifo, no un borrón. Prueba
  nueva `test/core/theme/inutil_refresh_glyph_test.dart` (44 pruebas locales
  en verde; `flutter analyze`: 0 issues).
- **Desaparece el salto «primero la interfaz vieja, luego la correcta».** El
  primer frame siempre encontraba `settingsControllerProvider` sin resolver
  porque ese proveedor hace I/O real de plataforma, así que `HomePage` caía a
  sus defaults (reproductor «Inútil Music» clásico, artwork cuadrado, Canvas
  apagado) y un segundo después se redibujaba con las preferencias reales. Se
  añadió `lib/core/startup/inutil_settings_hydration_gate.dart`, que pinta el
  esqueleto durante esos frames iniciales y entrega el shell ya hidratado; el
  lienzo animado aparece de una vez, sin flash intermedio. Pruebas
  `test/core/startup/settings_hydration_gate_test.dart` y
  `test/features/music/presentation/widgets/player_canvas_pending_test.dart`.
- **El panel Conectar ahora funciona como Spotify Connect.** Reescrito
  `inutil_connect_sheet.dart` (439 líneas): fila destacada «Este teléfono» con
  el título y el artista en curso en color de acento, insignia
  «Reproduciendo»/«En pausa» y el icono de plataforma (teléfono/PC/TV) a la
  derecha; equipos agrupados con sección «En otras redes» y subtitulo
  «en línea · red local» o «en línea · a distancia (por la nube)»; botón ancho
  «Transferir aquí» para traer la sesión a este equipo sin cerrar el panel.
  **Se quitó el mini reproductor embebido** —la tarjeta «Sesión de reproducción
  actual» con sus botones de anterior/reproducir/siguiente— porque en Spotify
  esa hoja solo lista dispositivos y Cesar pidió justo eso. Antes el panel
  mostraba «Buscando tus dispositivos…» girando para siempre aunque la cuenta
  tuviera 11 documentos `devices` publicados.
- **Quitar la app de la vista de recientes detiene la reproducción.** Faltaba
  la rama `taskRemoved` en `DesktopMediaSession`, así que `onTaskRemoved`
  terminaba en un `Future.value()` de no-op y el audio seguía sonando con la
  app ya muerta. Ahora `taskRemoved` llama a `playerController.stop()` igual
  que el botón detener; el puente con `audio_service` queda cubierto por
  `test/services/media_session/audio_service_desktop_media_session_test.dart`.
- **Las pruebas ya no se cuelgan: se rompió un ciclo de dependencias que sólo
  se veía en modo debug.** `playerControllerProvider` y
  `inutilPlaybackSyncProvider` se escuchaban mutuamente con `ref.listen`, y
  Riverpod sólo lo detecta en `kDebugMode`
  (`riverpod-3.4.3/lib/src/core/element.dart:1003`,
  `Ref._debugAssertCanDependOn`): por eso el APK de release funcionaba en el
  teléfono y `flutter test` nunca terminaba. Medido con un `ProviderObserver`,
  `PlayerController` caía en `AsyncError` con `CircularDependencyError` y
  `tester.pumpWidget(_testApp())` no retornaba (`timeout 110` → EXIT=124
  también sobre el commit sin mis cambios, o sea la traba venía del commit
  `6cf559ea` del 2026-11-17, no de mis cuatro ajustes). Como el proveedor de
  sincronización devuelve el singleton `InutilPlaybackSyncService.instance`, el
  controller ahora se suscribe a ese mismo objeto con `addListener` +
  `ref.onDispose(...)`: notifica lo mismo en el mismo momento y el grafo queda
  en un solo sentido. Medido: `timeout 110 flutter test test/widget_test.dart
  --plain-name 'renders Inútil Music shell'` pasó de EXIT=124 (sin retorno) a
  completarse en `00:01`, y `flutter test
  test/features/music/presentation/providers/audio_quality_upgrade_controller_test.dart`
  —el único prueba que depende del override de ese proveedor— sigue verde:
  **+52, All tests passed!**.
- **La tubería de Windows existía pero nunca había corrido.** En GitHub Actions
  `gh run list` devolvía `[]` (0 ejecuciones históricas) porque la rama por
  defecto `main` era un commit huérfano de documentación (`082848e`, sólo
  `README` del canal OTA) sin código ni workflows, y Actions sólo descubre
  workflows en la rama por defecto. Se añadió `desktop-builds.yml` a `main`
  (`2ab83db`, `[skip ci]`) y se alineó `FLUTTER_VERSION` a `3.50.0` (`865bdd2`)
  porque la primera ejecución dispatchada (run `44853194063`) falló con exit 65
  en «Required quality gate / Resolve dependencies»: `pub get
  --enforce-lockfile` reportaba `Would change 1 dependency … test_api 0.7.12
  (was 0.7.14)`, es decir el `pubspec.lock` lo generó un SDK más nuevo que el
  3.47.9 que pedía el workflow. El local coincide con el de CI: `flutter
  --version` → 3.50.0 / `dart --version` → 3.14.0.
- **El menú móvil de salida de audio ya no lanza una excepción al cerrarse.**
  `audio_routing_menus.dart` llamaba `ref.read(...)` dentro de `dispose()`,
  o sea después de que Flutter desmontara el widget, y Riverpod 3 lo castiga
  con `Bad state: Using "ref" when a widget is about to or has been unmounted
  is unsafe`. El servicio se captura ahora en la primera línea síncrona de
  `_init()` (`final service = _service = ref.read(...)`) y `dispose()` cierra
  la sonda con `unawaited(_service.stopWatching())`. Medido: la prueba
  `test/features/music/presentation/widgets/desktop_audio_output_menu_test.dart`
  pasó de **+8 -1** a **+9, All tests passed!** (EXIT=0).
- **En apaisado el reproductor ya no se recorta un píxel contra la barra del
  sistema.** La columna de controles medía **237 dp** contra los **236 dp** que
  le daban al marco 537×268 con inset inferior de 24, y Flutter lo avisaba con
  `A RenderFlex overflowed by 1.00 pixels on the bottom` — un corte de 1 px en
  la fila de utilidades del reproductor. Se rompió en `9c38523`, cuando la
  píldora `PlayerControlsCapsule` sumó `vertical: 2` de padding y
  `Border.all(width: 0.85)` a esa fila (+5.7 dp de alto); en el commit base del
  fork (`640348e`) la prueba estaba verde. Se recortaron 2 dp del hueco entre
  las etiquetas de tiempo y la barra de progreso **solo en apaisado**
  (`_Timeline`): la columna mide 235 y cabe con holgura, la barra conserva sus
  48 dp de objetivo táctil y en vertical la curva de huecos no se tocó. Medido:
  `player_controls_favorites_test.dart` pasó de **+226 -1** a **+227, All tests
  passed!** (EXIT=0 en 00:28).

- **Las 42 pruebas de `test/widget_test.dart` que el cuelgue tenía escondidas
  vuelven a pasar: `+127 ~11, All tests passed!` (EXIT=0).** Aparecieron cuando
  se rompió el ciclo de dependencias, porque hasta entonces `flutter test`
  nunca llegaba a evaluarlas. No se borró ni una aserción:
  `grep -c 'testWidgets('` = **112** en `HEAD` y **112** ahora, con los mismos
  nombres y sin duplicados. Cada una se re-afirmó contra el producto real y
  quedó documentada fila por fila en `docs/widget_test_root_causes_2026-11-21.md`
  con el `Actual:` medido y el commit que cambió la interfaz: `9c38523` (glifos
  `InutilGlyph`/`InutilIcon` en la barra de navegación, la píldora
  `PlayerControlsCapsule`, `TrackResultTile` rediseñada con `primary` al 0.09 +
  borde 0.35/1 px y el mini reproductor con alto condicional
  `max(96, pad+20)` = 116 en vez de 170, `_contextualGreeting`), `2f715bb`
  (pastilla 38→36 dp y la tarjeta `settings-spotify-import-hero-card` que
  agrandó la lista de Ajustes), `2ae9e6d`/`de65eaf`/`bf6a3b0` (secciones nuevas
  de Ajustes que empujaron fuera del viewport las tarjetas `settings-card-*`,
  que existen desde la base `640348e`), `6cf559e` y el esqueleto
  `settings-hydration-skeleton` de esta misma versión. Los arreglos son de
  **prueba**, no de producto: se asentaron los timers diferidos (`Timer.run` de
  `HomeRecommendationsController`, `music_providers.dart:2058`) y el fundido de
  entrada del slot de 320 ms antes del `tap`, y se añadieron dos ayudantes de
  harness (`_settleHomeFeed`, `_drainDeferredHomeRefresh`).

### Changed

- **La versión subió a `2.5.14+4272` porque, si no, estos arreglos nunca
  llegarían por OTA.** `lib/core/firebase/inutil_update_service.dart:69-73`
  define `updateAvailable = _compareSemver(latestVersion, instalada) > 0 ||
  belowMinSupported`: con un teléfono ya en `2.5.13` y un manifiesto
  `latest=2.5.13` la comparación da `0`, así que la app **nunca** ofrece el
  build que contiene estos arreglos y el `versionCode` (`+4271`) tampoco
  cambiaría. Se subieron al unísono —lo exige
  `test/core/constants/app_metadata_test.dart`, que compara los cinco números
  y pasó **+7, All tests passed!** (EXIT=0)— `pubspec.yaml` (`2.5.14+4272`),
  `lib/core/constants/app_constants.dart` (`appVersion = '2.5.14'`),
  `README.md` (`Current version: **2.5.14+4272**`),
  `packaging/windows/InutilMusic.iss` (`MyAppVersion "2.5.14"`, de ahí sale el
  nombre `InutilMusic-2.5.14-Windows-x64-Setup.exe` que genera CI) y la propia
  prueba de metadatos.

## 2.5.13+4271 — 2026-11-20

### Added

- **Los tres empaquetes publicados llevan por fin los dos servidores dentro del
  binario.** El release `2.5.12` se construyó sin los ajustes de endpoints, así
  que la app nunca llegó a apoyarse en el relay del S7 ni en el Worker cloud:
  medido con `unzip -p <apk> lib/arm64-v8a/libapp.so | strings` sobre el asset
  publicado en GitHub, `workers.dev` y `192.168.100.27` aparecían **0** veces
  (el asset es byte-idéntico al build local, `sha256 42a81121…`). Esta versión
  se construyó con `--dart-define=FB_RELAY_HOST=192.168.100.27` y
  `--dart-define=FB_CLOUD_RELAY_HOST=inutil-cloud-relay.scada-xiaomi-server.workers.dev`
  y los tres APK se verifican con la misma medición antes de subirlos.
- **Capa 2 de datos: la app se apoya en un servidor intermedio en la nube
  cuando el servidor de casa no está a mano**, y si el de casa se levanta a
  mitad de la sesión vuelve a él sola, en vez de quedarse toda la sesión
  hablando directo con Google. Pruebas:
  `test/core/firebase/relay_reachability_fallback_test.dart` pasa de 11 a 14
  pruebas y `test/core/firebase/cloud_relay_tier_test.dart` cubre el árbol de
  decisión `lanRelay → cloudRelay → google` sin levantar servidores.

### Fixed

- **El teléfono se pausa solo porque la nube nombraba un altavoz sin presencia
  viva.** `playback_session/current` declaraba como altavoz el id
  `c90ec6c7…`; su documento `users/{uid}/devices/…` **sí existe** (GET a Google
  responde `HTTP 200`, `isOnline=true`, `appVersion=2.5.12`), pero su
  `lastSeenMs` tenía **7 559 s (≈2 h)** de viejo y ni el PC (`/api/ping` vacío)
  ni la TV respondían; como **solo el altavoz escribe la sesión en la nube**, el
  teléfono se quedó de mando y su reproducción local se congeló. Prueba de que
  `isOnline` no es fiable: de los 11 documentos `devices` de la cuenta **4**
  dicen `isOnline=true` y los cuatro tienen `lastSeenMs` de 125 s, 7 486 s,
  7 559 s y 13 253 s. Por eso el fix valida contra `lastSeenMs`/`lanPeerTtl`,
  no contra `isOnline`. El id además se re-propagaba solo:
  `/api/session` del relay LAN responde con `remoteSession.toJson()` y
  `shouldAdoptDocument` usa `>=`, así que cada equipo que lo leía lo re-adoptaba
  y lo re-escribía, y el único escape existente se disparaba únicamente cuando
  un par vinculado desaparece de `_cloudDevices` —el fantasma nunca estuvo ahí.
  Ahora el altavoz nombrado se valida contra la presencia viva
  (`declaredSpeakerIsLive`, `_liveSpeakerIds()`: documentos `devices` dentro de
  `cloudPeerTtl` 90 s + pares LAN que respondieron dentro de `lanPeerTtl` 12 s +
  par vinculado + id cedido dentro de la gracia). Si el nombrado no late, el
  equipo que queda recupera el audio local en el siguiente sondeo y su propia
  escritura de sesión sobrescribe el fantasma, sin reiniciar la app. A/B medido
  en el Xiaomi `a586e98a` con el altavoz zombie re-inyectado cada 3 s para
  imitar su heartbeat: con el build anterior el audio real (`dumpsys
  media_session`) quedó clavado **75 s** en 99 476 ms y el documento en 98 067 ms,
  y solo se soltó al forzar el revert a mano; con este build el teléfono se
  recuperó **por sí solo en 3 s y en 6 s** en dos corridas independientes, con
  el audio avanzando **+3 000 ms** y **+7 001 ms** y sin tocar Firestore.
  Pruebas: 9 pruebas nuevas en
  `test/core/firebase/playback_session_staleness_test.dart` (18 → 27),
  `test/core/firebase/` completo **+149, All tests passed**, y `dart analyze`
  sobre el servicio editado: No issues found.
- Un desconocido que vea el código de emparejamiento en la misma red ya no
  puede cancelar el emparejamiento pendiente de otro: sólo se puede borrar
  estando firmado en la cuenta o mientras el código siga vigente. Desplegado y
  probado en vivo el 2026-11-20: código vivo → `DELETE` anónimo `200`; código
  vencido → `403 PERMISSION_DENIED`; el mismo `DELETE` con credencial → `200`.
- Las notas del diálogo de actualización se escriben en lenguaje de usuario:
  las que mencionan la nube de Google, el kill switch o los permisos de
  administración se colaban en la tarjeta y el diálogo las descarta
  (`_userFacingReleaseNotes`), así que el cartel salía vacío o con una sola
  línea genérica.

### Changed

- **La actualización a 2.5.13 es obligatoria: todo lo anterior queda sin
  soporte.** Se publicó `v2.5.13` en GitHub con `minSupportedVersion = 2.5.13`
  y `mandatory = true`; antes estaban `latestVersion=2.5.12`,
  `minSupportedVersion=2.5.0` y `mandatory=False`, o sea `belowMinSupported`
  era falso para cualquier versión instalada ≥ 2.5.0 y **nadie** estaba
  forzado a actualizar. El corte se puso en 2.5.13 y no en 2.5.10 porque
  2.5.10-2.5.12 sí traían el relay del S7 pero les faltaba la capa cloud y la
  re-sonda de recuperación, que es exactamente lo que les hace seguir
  hablando con Google y pagar la cuota que el relay ahorra. Medido tras
  publicar: `app_config/release` responde `2.5.13 / 2.5.13 / True`
  (`updateTime 2026-11-20T23:43:30Z`), lo mismo vía el relay de la LAN, y
  **anónimo sin sesión** desde la red de casa da `HTTP 200` con
  `latest=2.5.13 min=2.5.13 mandatory=True` en 0.27 s. De las 12 identidades
  registradas en `users/{uid}/devices`, **10** quedan por debajo del mínimo
  (2.5.8, 2.5.10, 2.5.11, 2.5.12 y una `pc-client-1.0`), 1 está al día y 1
  tiene `appVersion` vacío. OJO: el binario se subió **antes** de activar el
  kill switch, porque sin descarga posible la pantalla obligatoria deja a la
  gente atascada; medido desde la misma red del teléfono, `HEAD` del APK
  publicado responde `200`, `content-length=38339941`,
  `content-type=application/vnd.android.package-archive` en 0.36 s. Los tres
  APK verificados antes de subirlos: `versionName=2.5.13` con
  `versionCode` `6271`/`5271`/`8271` (`aapt`), y `strings` de `libapp.so`
  contiene una ocurrencia de `workers.dev` y otra de `192.168.100.27` en cada
  ABI. Las 6 notas publicadas pasan enteras el filtro `_userFacingReleaseNotes`
  (simulado contra el manifiesto vivo: 6 de 6 visibles).

## 2.5.12+4270 — 2026-11-20

### Added

- **Tier 2 de datos: el Worker cloud (`inutil_cloud_relay`) ya está conectado a la
  app.** `lib/core/firebase/relay_tier_selector.dart` (nuevo, 174 líneas) es el
  árbol de decisión **puro** `lanRelay → cloudRelay → google`: no toca la red ni
  `SharedPreferences`, así se prueba entero sin levantar servidores; las sondas
  viven en `FirebaseConfig` y le pasan el resultado como parámetro
  (`RelayTierInputs.lanReachable` es `bool?` porque `null` — todavía sin medir —
  NO es lo mismo que `false` para quien sí está en casa).
- Variables de build: `FB_CLOUD_RELAY_HOST` (vacío = exactamente el
  comportamiento de antes: relay LAN o Google), `FB_CLOUD_RELAY_SCHEME` (`https`
  por defecto; un valor inventado se normaliza a `https` para que un
  `--dart-define` mal escrito no inyecte texto dentro de la URL) y
  `FB_CLOUD_RELAY_PORT` (vacío = **sin** `:puerto` en la URL). La capa cloud se
  usa **sin sonda de TCP**: sondear `workers.dev` en cada arranque costaría
  requests del plan gratuito del Worker (100k/día) y no aportaría nada.
- El hueco que cierra: `relayAwareUrl` solo sabía construir `http://host:puerto`,
  así que un build horneado con `FB_RELAY_HOST` fuera de la LAN de la casa caía
  siempre en Google y pagaba la cuota entera (medido 2026-11-20: **94,114
  lecturas/día = 188 %** del límite de 50,000 del plan Spark).
- Build medido:
  `flutter build apk --release --dart-define=FB_RELAY_HOST=192.168.100.27 --dart-define=FB_CLOUD_RELAY_HOST=inutil-cloud-relay.scada-xiaomi-server.workers.dev`
  → `build/app/outputs/flutter-apk/app-release.apk` **71,466,623 B** (Gradle
  237.2 s, `build_exit=0`), y `unzip -p … lib/arm64-v8a/libapp.so | strings`
  contiene las dos cadenas horneadas (1 ocurrencia de cada) ✓. OJO: ese APK es
  `versionCode 4270` y el Xiaomi tiene instalado `6269` (`2.5.11`), así que
  `adb install -r` lo rechaza con `INSTALL_FAILED_VERSION_DOWNGRADE`; la
  instalación le toca al pipeline de release (`tool/publish_release.sh` arma
  `app-arm64-v8a-release.apk` = 38,338,609 B, no el fat APK).
- Pruebas: `test/core/firebase/cloud_relay_tier_test.dart` (nuevo) y la corrida de
  `test/core/firebase/` queda en **+140 verdes, 1 saltada** (antes `+116 ~1`);
  `dart analyze --no-fatal-warnings lib test` — los 412 ficheros de `lib/` más los
  296 de `test/` — dice **`No issues found!`** (exit 0).

### Fixed

- **La app vuelve sola al relay del S7 cuando el relay se levanta**, en vez de
  quedarse toda la sesión hablando con Google. Medido el 2026-11-20 con las apps
  abiertas y el relay reiniciado / el S7 rebooteado: 9 muestreos de `/healthz`
  cada 60 s dieron `cache_hits` 0,0,0,0,2,2,2,2,2 aunque el teléfono estaba
  escuchando `0.0.0.0:8080` con `oom_score_adj -1000`; `ss` de la PC y del Xiaomi
  no tenían ni una conexión a `192.168.100.27:8080`; y el logcat del teléfono
  registró `10:45:20 Relay del S7 sin respuesta en users/R5Le…/playback_session/current:
  reintento directo a Google` seguido de **11 PATCH de heartbeat rechazados con
  `401 Missing or invalid authentication`**, uno cada 30 s entre 10:58 y 11:03.
  Con las apps enganchadas a Google se paga exactamente la cuota que el relay
  ahorra: medido en la ventana 03:43→09:38 de ese mismo día, **94,114
  lecturas/día y 8,100 escrituras/día** habrían pagado sin el relay (188 % y
  40.5 % de los límites 50,000/20,000 del plan Spark).
- Cómo queda cerrado: `markRelayUnreachable()` (`firebase_config.dart:202`) deja
  la marca de recuperación **solo si estábamos usando el relay** — es la señal
  exacta de "esto era mío y se acaba de caer"; `relayRecoveryWorthy` la consulta;
  y `_maybeReprobeRelay()` (`firebase_playback_sync_service.dart:906`) re-sondea
  a lo sumo **una vez cada 45 s**, colgado del tick de 3 s que ya existe (no
  añade timers nuevos, así que tampoco deja pruebas de arranque pendientes).
  Cuando encuentra el relay, las lecturas y las escrituras vuelven a pasar por el
  teléfono sin reiniciar la app. `main.dart:95` además pide la re-sonda cuando la
  sonda de arranque falló **pero** este equipo declaró vivo al relay en un arranque
  anterior (`inutil_relay_reachable_v1`), que es justo el caso del S7 levantándose
  despacio del reboot con la app ya abierta. Un build sin `FB_RELAY_HOST` o un
  usuario fuera de la LAN que nunca lo vio vivo no dejan marca, o sea nunca se
  sondea por sondear ni se pagan timeouts de más.
- Pruebas: `test/core/firebase/relay_reachability_fallback_test.dart` pasa de 11 a
  **14** pruebas. Las 3 nuevas son: `tras caerse MIENTRAS se usaba quiere
  re-sondear, y se recupera sola cuando el relay vuelve`, `un equipo que nunca usó
  el relay no pide re-sonda: el usuario off-LAN no paga timeouts cada 45 s` y
  `noteRelayRecoveryWanted es el caso del S7 levantándose con la app ya abierta
  (cache true + sonda de arranque fallida)`. La corrida de `test/core/firebase/` +
  `test/core/constants/` queda en **123 verdes y 1 saltada** (la saltada es
  `inutil_cloud_backup_emulator_test`, que exige `--dart-define=FB_EMULATOR=true`
  con el emulador levantado) y `flutter analyze lib/` sin hallazgos.

## 2.5.11+4269 — 2026-11-20

### Added

- **La app avisa sola cuando hay versión nueva:** la puerta de actualizaciones ya consultaba el manifiesto al arrancar y al volver de segundo plano, pero sólo pintaba algo cuando la actualización era obligatoria o la versión instalada caía bajo el mínimo soportado. Con `mandatory:false` y `min:2.5.0` —el estado normal de los releases— un `2.5.10` publicado contra un `2.5.9` instalado no generaba ninguna señal visible: medido en el Xiaomi (`2201122G`, Android 15), `versionName=2.5.9 versionCode=6267`, manifiesto de GitHub alcanzable (RTT 54 ms, 0 % pérdida) y ni un cartel. Ahora, si existe una versión superior opcional, la app muestra el mismo diálogo de novedades como cartel descartable encima de la interfaz (el interior sigue usable, `InutilForceUpdateScreen` no aparece) y al cerrarlo recuerda la versión pospuesta en `inutil_update_notice_snoozed_for`, así que el mismo aviso no vuelve a salir en los siguientes arranques; cualquier manifiesto con una versión superior lo reactiva.

### Fixed

- Los botones del diálogo de actualización caben en el teléfono: `Row(mainAxisAlignment:end)` con `Más tarde` + `Actualizar v2.5.10` desbordaba **83 px** dentro de los 396 px de ancho del diálogo y el botón principal quedaba recortado por el `Clip.antiAlias` del `Material`, así que no se podía pulsar; se cambió a `Wrap` con `spacing:8` y `runSpacing:8` alineado a la derecha.
- Las 3 pruebas de la puerta de actualizaciones que venían fallando desde el rediseño de la interfaz pedían rótulos inexistentes (`⚠ LA APP QUEDÓ DESHABILITADA`, `ACTUALIZACIÓN OBLIGATORIA`, `Descargar e Instalar v2.1.0`); se alinearon con los reales (`ACTUALIZACIÓN REQUERIDA` / `ACTUALIZACIÓN DISPONIBLE`, `Actualizar v…`, `Más tarde`) y se documentó el baseline: `git stash` + corrida limpia confirmaron que esas 3 fallaban antes de este cambio.
- Pruebas: la batería de la puerta de actualizaciones pasa de 11/14 a **16/16** (5 pruebas nuevas del aviso: aparece sin bloquear, se pospone y no reaparece, se reactiva con una versión superior, no molesta estando al día, y la actualización forzosa sigue sin ofrecer `Más tarde`).

## 2.5.10+4268 — 2026-11-20

### Fixed

- La app deja de depender de estar en la red de casa: el build horneado con `--dart-define=FB_RELAY_HOST=192.168.100.27` redirigía TODAS las lecturas de Firestore y Storage a una IP privada, así que a un usuario fuera de esa LAN no le respondían ni la sincronización ni el manifiesto de OTA (que también se lee por ahí). Al arrancar, la app sondea el relay durante 1.2 s y si no responde encamina Firestore y Storage directo a Google: el mismo binario sirve dentro y fuera de la LAN, y el ahorro de cuota se conserva en casa.
- Y si el relay se cae a media sesión, el primer error de conexión (`Connection refused`, `SocketException`, `TimeoutException`) lo marca como caído y la petición se reintenta una sola vez contra Google, sin reiniciar la app y sin volver a tocar el relay. Los errores con código HTTP (403/429/500) no se reintentan: ése sí llegó a un servidor, y reintentar un `429 RESOURCE_EXHAUSTED` a ciegas sólo gastaría más cuota.
- Cada arranque vuelve a sondear, así que llevar el laptop de la casa a otra red se autodetecta solo: no hay que reinstalar ni reconfigurar nada. El resultado se cachea (`inutil_relay_reachable_v1`) sólo como telemetría.
- Pruebas: 238/238 verdes y `flutter analyze` sin hallazgos. Se añadieron 11 pruebas del fallback (`test/core/firebase/relay_reachability_fallback_test.dart`) y se cerró la cadena de versión que el test `app_metadata_test` exige (`pubspec.yaml`, `README.md`, `packaging/windows/InutilMusic.iss` y `AppConstants.appVersion` estaban desalineados desde que se subió `pubspec` a 2.5.9+4267 sin tocarlos; ese test venía fallando desde entonces).

## 2.5.9+4267 — 2026-11-20

### Fixed

- Se acabó el micro corte que se oía al decir "mejorando calidad de sonido": el relevo entre los dos decks pasa de 250 ms a un solo tick de 20 ms, así que la grabación saliente se silencia en el mismo tick en que la entrante llega a ganancia completa y desaparece la cancelación en peine (comb filtering) entre dos copias idénticas desfasadas.
- Arreglado el maximizado en la PC: al expandir la ventana GTK pintaba la app en un rectángulo pequeño de la esquina superior izquierda con el resto negro. El runner publicaba `PPosition 0,0` en `WM_NORMAL_HINTS`, la decoración del cliente bajo XWayland rechazaba la geometría del compositor y la ventana saltaba a la esquina; se eliminó `gtk_window_set_position(GTK_WIN_POS_CENTER)` y el round-trip 1332x819 → 1853x1048 → 1332x819 se verifica sin saltos.
- El "reproductor colgado" en la misma canción: el documento `playback_session/current` podía decir `isPlaying:true` con la posición congelada 28 min (medido: 5611/186161 ms) y el mando seguía fingiendo que sonaba. Ahora una sesión que dejó de refrescarse más de 20 s es un fantasma (`sessionIsGhost`, `visibleSession`), el `PlayerController` descarta ese estado espejado y la barra avanza con `estimatedPositionMs` entre las escrituras de 8 s del altavoz real.
- Sincronización sin cuota de Firebase: `firestoreBaseUrl` y `storageBaseUrl` resuelven contra `FB_RELAY_HOST`/`FB_RELAY_PORT` (`--dart-define`), el relay propio del S7 (`192.168.100.27:8080`) absorbe los `429 RESOURCE_EXHAUSTED` que frenaban la app; la autenticación sigue en Firebase real y, con `FB_RELAY_HOST` vacío, se conserva intacto el fallback a la nube de Google.
- La app de PC deja de reabrirse sola al cerrarla: se retira el autostart (`~/.config/systemd/user/inutil-music.service` y su symlink en `default.target.wants`) y el auto-restart; no hay servicio systemd para `com.inutilmusic.app`.
- Pruebas: 210/210 tests verdes (crossfade 15, just_audio 78, media_kit 47, upgrade de calidad 52, staleness de sesión 18) y `flutter analyze` sin hallazgos. El fixture del upgrade de calidad ya no cuelga para siempre porque levanta el ciclo real `PlayerController` ↔ `InutilPlaybackSyncService`.

## 2.5.8+258 — 2026-11-18

### Added

- **Inútil Connect funciona a distancia (sin mismo Wi-Fi), como Spotify Connect:** cada equipo publica su presencia en `users/{uid}/devices` (latido cada 30 s) y el panel *Conectar* ahora enumera los dispositivos de la cuenta aunque no estén en la misma red, distinguiendo «red local» de «a distancia (por la nube)».
- Cola de comandos en la nube `users/{uid}/commands`: play/pause/skip/seek/playTrack viajan por Firestore cuando el puerto LAN no es alcanzable, con ventana de sondeo rápido de 8 s tras enviar y expiración a los 10 min para que un comando no se ejecute fuera de tiempo.

### Changed

- El vinculado automático elige primero un PC (los equipos de escritorio suenan); un celular de la misma cuenta nunca se selecciona solo, se escoge desde el panel.
- Los comandos enviados a apps 2.5.7 o anteriores usan además el puente heredado `pendingCommand*` del documento de sesión, compartiendo el mismo identificador para que la orden se ejecute una sola vez.
- El panel de QR deja de consultar la bandera interna de pruebas de `InutilAuthService`; las pruebas de widget inyectan su propia fábrica de sesiones con `MusicQrLoginPanel.debugSessionFactory`.

## 2.5.7+257 — 2026-11-18

### Added

- Inicio de sesión en la PC escaneando un código QR con el celular (igual que en la app de TV): la pantalla de acceso del escritorio muestra un QR en vivo con su código alternativo `XXXX-XXXX`; el celular, desde *Mi cuenta → Iniciar sesión en PC*, escanea el QR con la cámara o escribe el código.
- Cifrado de extremo a extremo de la sesión compartida: AES-256-CBC + HMAC-SHA256 (Encrypt-then-MAC) con clave efímera que solo viaja dentro de la imagen QR (o derivada del código manual); Firestore nunca almacena la clave ni el token en claro. Sesión temporal `music_pairing/{code}` con expiración de 3 minutos y limpieza automática.
- Permisos de cámara en Android (`CAMERA`, opcional) y iOS (`NSCameraUsageDescription`) exclusivamente para el escáner de vinculación.

### Changed

- Reglas de Firestore endurecidas para `music_pairing/{code}`: lectura directa permitida, enumeración bloqueada, creación limitada a documentos `pending` sin campos extra y aprobación solo para usuarios autenticados (`pending → approved`).

## 2.5.6+256 — 2026-11-18

### Changed

- Eliminadas todas las referencias internas heredadas restantes (colección de Favoritos unificada a `inutil:favorites`, carpeta `Inutil-Music`, identificador Apple `com.inutilmusic.app`, esquema `inutilmusic://`, cabecera CSV `InutilCsvVersion`, claves de sesión y pie de Ajustes/instalador/CI).
- Migración automática segura al abrir la base de datos y restaurar respaldos en la nube para conservar las colecciones de Favoritos existentes bajo `inutil:favorites`.
- Empaquetados `LICENSE` y `THIRD_PARTY_NOTICES.md` dentro de los assets en todas las plataformas (incluido APK Android) con visor integrado de *Licencias de código abierto* en Ajustes para cumplimiento total BSD-2/MIT/Apache-2.0.

## 2.5.5+255 — 2026-11-18

### Fixed

- Reemplazado el icono monocromático heredado de notificación/controles multimedia en Android (`drawable-nodpi/ic_stat_inutil_music.png`) por la silueta oficial **iM** de Inútil Music.
- Asignación explícita del icono empaquetado sobre cada `GtkWindow` en Linux (`apply_bundled_window_icon`), poblando `_NET_WM_ICON` bajo X11/XWayland para que el dock, Alt+Tab y barra de títulos muestren siempre el icono **iM**.
- Eliminados archivos fuente heredados del proyecto base en `assets/branding/` y `assets/icons/source/icon-edit-prompt.txt`.

## 2.5.4+254 — 2026-11-18

### Fixed

- Corrección definitiva de ventana en Linux con GPU NVIDIA (`Flutter 3.50`): en sistemas donde GLVND carga `10_nvidia.json`, el lanzador nativo enruta automáticamente EGL por `50_mesa.json` evitando el defecto del compositor OpenGL (`#195885`) que recortaba la app al cuarto inferior izquierdo tanto en XWayland como en Wayland nativo.
- Eliminados los iconos heredados en `macos/`, `ios/`, `windows/runner/resources/app_icon.ico`, `assets/icons/source/ico.png` y el paquete Linux (`data/com.inutilmusic.app.png`); todas las plataformas usan ahora exclusivamente el icono oficial **iM** de Inútil Music.

## 2.5.3+253 — 2026-11-18

### Fixed

- Corrección crítica de renderizado y centrado en escritorio Linux (Wayland/GNOME): el ejecutable ahora utiliza Wayland nativo cuando `WAYLAND_DISPLAY` está activo en lugar de forzar XWayland (`GDK_BACKEND=x11`), eliminando el recorte al cuarto inferior izquierdo de la ventana bajo `xwayland-native-scaling` y centrando la ventana principal en X11 y Windows.

## 2.5.2+252 — 2026-11-18

### Fixed

- Mejora profunda del motor de coincidencia al importar playlists de Spotify y archivos CSV (`LibraryCsvImportService`): búsqueda progresiva con respaldo limpio (elimina etiquetas como `(feat. ...)`, `- Remastered`, `(Deluxe)`, `[Explicit]` y álbumes cuando la consulta literal falla), puntuación multi-artista y detección de videos oficiales con formato `Artista - Título`.
- Eliminación de falsos rechazos por ambigüedad cuando YouTube devuelve múltiples subidas limpias de la misma canción (por ejemplo, versión Topic + Official Audio/Visualizer).
- El diálogo de importación de Spotify (`InutilSpotifyImportDialog`) ahora muestra la lista desplegable exacta de canciones no encontradas cuando alguna pista no pudo resolverse.

## 2.5.1+251 — 2026-11-18

### Fixed

- Restauración automática inmediata de playlists y biblioteca al iniciar sesión tras reinstalar la app o borrar datos (`_LocalArtworkMaintenance` ahora reacciona en tiempo real a `inutilAuthProvider`), eliminando la condición de carrera que dejaba la Biblioteca vacía al entrar.
- Respaldo y restauración completos de canciones dentro de playlists de catálogo (`playlist_items` + `catalog_tracks` en bloques `backup_entries_*`), incluyendo listas importadas de Spotify/CSV y canciones añadidas sin descarga local, con saneamiento seguro de `local_track_id` ante claves foráneas.
- Sincronización inmediata a la nube al finalizar importaciones de Spotify/CSV (`LibraryCsvTransferController`), debounce de guardado reducido a 5 s y protección anti-sobrescritura que fusiona el respaldo remoto antes de subir cambios locales.
- Botones directos **«Restaurar listas»** y **«Respaldar ahora»** en el diálogo **Mi cuenta** para sincronizar o recuperar bajo demanda en cualquier momento.

## 2.5.0+250 — 2026-11-18

### Performance

- Desbloqueo automático de tasa de refresco alta nativa en Android (90 Hz / 120 Hz+) en `MainActivity` para desplazamientos, transiciones de pestañas y gestos ultra fluidos.
- Optimización del pipeline GPU y decodificación de carátulas: submuestreo inteligente (`<= 256 px` con `FilterQuality.low`) en fondos con desenfoque intenso (`PlaybackArtworkBackdrop` y fondo Canvas de Spotify), aislamiento con `RepaintBoundary` en cabeceras/tarjetas/listas y mayor capacidad de `imageCache` (`240` entradas / `64 MiB`) para cambiar de pestaña sin re-decodificaciones.
- Eliminación de reconstrucciones innecesarias por ticks de posición de 200 ms en `InutilConnectSheet` y en letras flotantes de Canvas (búsqueda binaria `O(log N)` y selección por cambio real de verso).
- Reemplazo de `GridView(shrinkWrap: true)` en accesos rápidos de Inicio por una rejilla de paso único (`Column`/`Row`) con aislamiento `RepaintBoundary` en tarjetas de Inicio, Biblioteca, Música local y Ajustes.
- Última actualización marcada como obligatoria; a partir de la próxima versión las actualizaciones serán opcionales salvo emergencia.

## 2.4.1+241 — 2026-11-18

### Fixed

- Nuevo motor nativo dedicado exclusivamente al vídeo de fondo en Android (`InutilCanvasEngine`, cero renderers de audio, cero `AudioTrack`/`AudioFocus`, hilo propio de baja prioridad y bucle en hardware sin lecturas GPU), más caché local previa de Video Previews, eliminando los micro-tirones al cargar y al reiniciar el bucle sobre la pista musical.

## 2.4.0+240 — 2026-11-18

### Added

- Nuevo recorrido guiado interactivo de 8 pasos al abrir la app por primera vez (con demos reales para tocar, deslizar a la cola, guardar favoritos y personalizar colores), repetible en cualquier momento desde Ajustes → Acerca de → «Recorrido guiado interactivo».
- Gestión automática de cupos gratuitos por inactividad con pantalla amigable de pausa («Tu música sigue a salvo en la nube») y botón de solicitud de reactivación a un toque.

## 2.3.0+230 — 2026-11-18

### Added

- Nuevo «Inútil Wrapped» (Resumen del Año animado tipo Stories estilo Spotify): horas escuchadas, artista #1, canción favorita, Top 5, personalidad musical, tarjeta compartible y agradecimiento de fin de año con respaldo en la nube.
- Acceso directo en Ajustes → Acerca de → «Tu Resumen del Año» para revivirlo cuando quieras, además de lanzamiento automático en temporada de fin de año.

### Fixed

- Restauración completa de la playlist Favoritos y actualización inmediata de la Biblioteca tras reinstalar la app o borrar datos e iniciar sesión nuevamente.

## 2.2.1+221 — 2026-11-17

### Added

- Tarjeta destacada «Listas de Spotify» en Ajustes con el mismo estilo elegante e integrado que la tarjeta de YouTube Music.
- Pop-ups creativos rotativos de apoyo al creador (8 mensajes distintos que cambian cada vez) con arquitectura modular lista para futuras campañas.
- Selector propio de salida de audio en móvil integrado 100 % con el tema activo de la aplicación.

### Fixed

- Eliminados micro-cortes de audio al navegar entre pestañas en Android (desactivado offload scheduling inestable, evitada destrucción diferida del decoder Canvas fuera de pantalla y optimizado el blur GPU).
- Unificados al 100 % con el tema nativo de la app el panel «Conectar a un dispositivo» y la tarjeta superior de cuenta en Ajustes.
- Retirado el icono redundante de YouTube Music de la cabecera de Inicio (ya disponible en Ajustes).

## 2.2.0+220 — 2026-11-17

### Added

- Nuevo sistema de iconos vectoriales propios de Inútil Music con estado delineado en reposo y relleno elegante al activar en navegación, cabecera, reproductor y ajustes.
- Pantalla de Inicio renovada: saludo contextual, píldoras rápidas de filtro (Todo, Recientes, Álbumes y Mixes, Artistas), cuadrícula compacta 2x3 de acceso rápido y actualización deslizando hacia abajo.
- Desliza cualquier canción a la derecha en listas para añadirla inmediatamente a la cola de reproducción.
- Temporizador de sueño accesible a un toque directo desde el reproductor.

### Changed

- Nuevo lenguaje visual propio con tarjetas redondeadas, carátulas suaves, filas de canciones limpias sin bordes pesados y medallas con degradado en Ajustes.
- El mini reproductor ahora se oculta automáticamente cuando no hay nada en reproducción para aprovechar mejor la pantalla.

## 2.1.3+213 — 2026-11-17

### Changed

- Transición cinematográfica suave (desvanecido lento con curva cúbica) al pasar de la carátula estándar al reproductor Canvas a pantalla completa y al cambiar de canción.
- Fondo ambiental difuminado y aparición gradual del video Canvas en pantalla completa para una experiencia visual fluida y descansada a la vista.

## 2.1.2+212 — 2026-11-17

### Added

- Reproductor Canvas a pantalla completa estilo Spotify: video oficial en loop de borde a borde, letra sincronizada flotante en vivo, mini portada, botón circular de favoritos, controles modernos y tarjeta inferior «Muestra de la letra».

### Fixed

- Corregidos gestos de retroceso y botón de cierre en el diálogo de actualizaciones cuando la app ya está al día.
- Acentos y caracteres especiales mostrados correctamente en las notas de actualización.

## 2.1.1+211 — 2026-11-17

### Added

- Video Previews estilo Spotify en canciones, perfiles de artistas y álbumes, con visor vertical a pantalla completa.
- Optimización de audio para conexiones lentas: buffer ampliado, reconexión automática y ajuste inteligente de calidad para evitar cortes.

### Changed

- Pantalla de Inicio más limpia y profesional; «Importar desde Spotify» organizado dentro de Ajustes → Almacenamiento y datos.
- Diálogos de cuenta, dispositivos, importación y actualizaciones unificados con el tema nativo de la app.
- Al cerrar sesión, la reproducción se detiene inmediatamente y limpia la cola activa.

## 2.1.0+210 — 2026-11-17

### Added

- Licencias por cuenta en Firestore: el registro queda en estado `pending` y
  nada suena hasta que la administración concede la vigencia; el panel de
  administración concede, suspende y reactiva cuentas desde la app.
- Respaldo en la nube del perfil, playlists, biblioteca y ajustes en
  `users/{uid}/data`, con restauración automática al reinstalar la app o
  borrar sus datos y sincronización periódica/por pausa.
- Una sola sesión de teléfono por cuenta: el teléfono reclama el dispositivo
  activo y un segundo teléfono desplaza al primero; la PC sigue funcionando
  como altavoz/control remoto por LAN.
- Kill switch de actualizaciones forzadas: `app_config/release` publica
  `minSupportedVersion` y las versiones anteriores quedan bloqueadas con
  pantalla de actualización obligatoria que no se puede descartar.
- Reglas de Firestore endurecidas (bootstrap del administrador, roles,
  respaldo propio, reclamo de teléfono y publicación del manifiesto) y su
  verificación end-to-end contra el emulador.

### Changed

- Sin credenciales embebidas en el cliente: el único secreto es el identificador
  público del proyecto Firebase; la seguridad la ejercen las reglas.

## Unreleased

### Added

- Audio Sources in Integrations, with mandatory YouTube Music and optional
  JioSaavn enabled by default. Data saving offers one quality choice on desktop
  and Wi-Fi/cellular profiles on mobile, also applied to downloads.
- Background same-recording JioSaavn quality upgrades that reuse the existing
  standby playback deck, retain queue/position/catalog metadata and fall back
  to YouTube when no verified higher-quality recording is available.
- Actual Low/Standard/High audio quality and current-track upgrade status in a
  headphones capsule beside the playback times in all player styles, localized
  in all seven languages.
- Read JioSaavn's actual codec, declared bitrate, sample rate and channels with
  the shared local MP4/AAC parser and a bounded, cached header lookup.
- Embed title, artist, album and cached artwork in compatible M4A/audio MP4
  (AAC/ALAC), MP3, FLAC, Ogg Opus/Vorbis, WAV and APE files, plus text tags in
  audio-only WebM/Matroska Opus/Vorbis downloads. WebM artwork remains cached
  separately, preserving its container and filename.
- Detect metadata containers from file contents and share format-specific
  comment/picture handling, bounded copying and validated atomic publication,
  without transcoding the audio. Metadata is written in a bounded background
  task before library publication, with atomic replacement and the original
  file retained when tagging fails or a container layout is unsupported.
- Update existing downloaded files from their saved library metadata through
  the downloaded-songs menu, without new network requests.

## 1.3.1+131 — 2026-11-12

### Added

- The player now supports higher quality audio when available.
- Added the new Spotify Style player.
- Added filtering options in the Local music tab.
- Added support for word-synchronized lyrics when word timing is available,
  with line-by-line synchronization retained as the fallback.
- Custom artwork for saved playlists, including Favorites. Tapping the cover
  offers Random or Custom, with gallery selection and the shared square crop
  editor. Saved covers are reused by library rows, playlist headers, backgrounds
  and playlist pickers, and remain available after media moves or ZIP restores.

### Changed

- Improved and optimized the layouts of the player styles.
- Improved the design of the Settings tab.
- Playback waves now share the artwork color extraction and cache used by
  playback menus, retaining the app accent when artwork is unavailable.
- Updated the minimum Flutter version and CI builds to stable 3.47.9.
- Retained Liquid Glass filters and painted optics during navigation, with
  full droplet growth and refraction reserved for dragging.
- Shortened navigation droplet travel to 220 ms and retained its optical
  subtree while moving between tabs.
- Hidden the bottom menu and mini player while the software keyboard is
  visible, retaining their state without painting or running animations.
- Changed keyboard chrome transitions to a subtle 2% zoom and fade: 100 ms
  to reappear and 80 ms to hide, starting immediately when visibility changes.
- Resumed visible glass effects 50 ms after the last keyboard inset change.

### Fixed

- Prevented interrupted remote loads from restarting the newly selected song
  after rapid skips.
- Removed lower-edge seams from expanded animated artwork and Spotify Canvas
  without adding video decoders or blur passes.
- Preserved full-player artwork through its exit transition.

## 1.2.9+129 — 2026-10-12

### Added

- Added desktop LIVE widget style selection with Classic and Wave previews.
- Added a home-screen player widget.
- Added custom app backgrounds using images selected from the gallery.
- Added app-wide font customization.
- Added multi-selection in albums, mixes, and search results, with actions to
  add the selected songs to a playlist or download them.
- Added Portuguese, French, Korean, Chinese, and Japanese language support.

### Changed

- Optimized animated artwork performance.
- Improved interface performance and smoothness.
- Album, mix, and artist backgrounds now inherit a subtle gradient from their
  cover artwork.

## 1.2.8+128 — 2026-09-17

### Added

- Added the Classic Vinyl full-player style with a rotating record, animated
  tonearm, responsive control spacing, and portrait/landscape adaptation.
- Added conservative Android silence skipping for streamed and downloaded
  tracks. RMS hysteresis, musical-peak protection, preserved margins, and
  separate edge/internal thresholds avoid cutting quiet passages, reverb, and
  intentional short pauses while remaining compatible with crossfade.
- Added mobile mini-player navigation gestures: swipe left for Next and right
  for Previous. The content follows the finger with bounded resistance, short
  drags settle without navigating, and screen readers expose equivalent
  actions.
- Added a timed wave indicator for instrumental gaps in synchronized lyrics.
  It fills until the next lyric and stops ticking while paused or when reduced
  motion is enabled.

### Changed

- Completed responsive horizontal layouts for the full-player styles, with a
  large artwork area on the left and metadata, timeline, and controls using the
  available space on the right across compact and large phones.
- The full player and Lyrics now keep the same dark playback presentation when
  the application theme is Light. Browsing, queues, popup menus, and settings
  continue to follow the selected application theme.
- Retuned lyric line changes and automatic recentering for quicker but smoother
  movement without opacity, scale, or scroll snaps during short lines and
  seeks.
- Refined Expanded artwork to preserve more of the lower cover before it blends
  into the background, and made animated-cover motion slightly more visible
  without changing the particle treatment.
- Reduced unnecessary rebuilds, filtered layers, and competing animation work
  across playback, lyrics, navigation, library cards, marquees, equalizers,
  progress bars, and wave controls for steadier frame delivery.
- Hardened TikTok LIVE connection bootstrap with alternate page discovery,
  coherent signing fallbacks, retry classification, bounded backoff, and stale
  attempt isolation so active rooms reconnect more reliably.

### Fixed

- Kept Android playback position synchronized after silence is shortened,
  including after backward seeks and for both streamed and downloaded tracks.

## 1.2.7+127 — 2026-09-08

### Added

- Added a responsive Search discovery grid with localized YouTube Music moods
  and genres. It keeps an offline-safe curated catalog and falls back to the
  regular music search when a remote category layout is unavailable.
- Added the Expanded artwork style, which extends and blurs the cover
  continuously in both full-player layouts.
- Expanded TikTok LIVE command permissions with audience filters for Everyone,
  Followers, Moderators, and Subscribers.
- Added Local LIVE overlay on Windows: a transparent, loopback-only web overlay
  at a TikTok LIVE Studio-compatible local domain. It shows the current song,
  playback progress, artwork, and up to four upcoming LIVE requests.

### Changed

- Improved animated artwork with smaller and more varied particles, mixed
  focus, smoother trajectories, and more natural wind-like movement.
- Refined the Local LIVE overlay with compact cards, elapsed and duration
  counters, artwork-aware accent colors, an inline Inútil Music logo beside the
  current song title, and keyed queue transitions without flicker when requests
  are added, removed, or updated.
- Hardened Local LIVE overlay startup on Windows with strict loopback DNS and
  HTTP health verification, bounded retries, complete socket cleanup, and
  distinct diagnostics for occupied or reserved ports, cancelled elevation,
  unavailable PowerShell, and managed-device policy blocks.

### Fixed

- Fixed delayed song and video artwork loading in search, playback, and
  downloaded/offline tracks by preserving and resolving the correct cached
  artwork source.

## 1.2.6+126 — 2026-09-02

### Changed

- Added the native iOS 13+ runner and completed the mobile platform routing for
  playback, background audio/Now Playing, secure embedded account login,
  headless WebView challenges, downloads, TikTok LIVE, deep links, local
  Media Library songs and artwork, and document-picker backup/CSV export. iOS
  now rebuilds sandbox-relative media paths after container changes, uses the
  bounded mobile stream cache, and is validated in CI with focused tests plus
  unsigned simulator and Release device builds. CI packages the device build
  as `InutilMusic-<version>-iOS-unsigned.ipa` for use as input to external
  signing or sideloading tools; the artifact is not directly installable until
  such a tool signs or re-signs it. Existing Android, Windows, Linux, and macOS
  platform paths remain unchanged.
- Added an optional cross-platform Liquid Glass appearance for application
  surfaces and the mini player, including neutral transparency, continuous
  superellipse clipping, uniformly backdrop-adaptive edge refraction, and
  hover-only droplets implemented entirely in Flutter. Song and Settings
  cards retain their regular Material treatment, and tab headers remain
  edge-to-edge instead of becoming rounded glass cards. Light mode now adds a
  milky-white veil and an exterior-only shadow so controls remain legible
  without giving translucent light surfaces a gray cast. Its navigation icons
  and mini-player metadata use pure black for reliable contrast. Dark glass
  now uses a lighter neutral wash and hover droplet so more backdrop chroma
  remains visible without changing its adaptive rim. Edge-to-edge tab headers
  now use one flat glass wash without the capsule shadow, Fresnel rim, or
  duplicate Material overlays that previously appeared as stacked rectangles.
  Accent and Transparent optics remain unchanged.
- In Accent and Transparent modes, bottom navigation now hides smoothly during
  downward browsing and returns on upward scrolling while the mini player
  occupies the released space. Liquid Glass instead compacts into an animated
  Home, mini-player, and detached Search row; Home or upward scrolling expands
  the full Home, Local, Library, and Settings menu again. The compact mini
  player now keeps its full translated hit-test area, so taps always open the
  player instead of reaching the browsing content underneath.
- The compact Liquid Glass Home control is now icon-only, matching the detached
  Search control while retaining its full accessible label and tap target.
- Appearance settings now offer Inútil Music and Apple Music Style full-player
  layouts. The Apple layout uses the artwork-blurred background, compact square
  cover, inline favorite/menu actions, remaining-time seek bar, Apple-like
  transport and volume rows, and the supported Lyrics, shuffle, repeat, and
  queue actions. Its cover flexes so standard phones from 320x568 upward and
  mobile landscape keep the complete player in one non-scrolling viewport;
  only extreme reduced-height or 300-percent accessibility layouts retain a
  scroll fallback. The Apple layout uses uniform 7 px progress and volume
  tracks without circular indicators, while Inútil Music retains its animated
  wave seek bar and compact volume thumb. Metadata actions align with the
  artist row, transport controls use the reference proportions, and time
  labels follow the track insets. Share now lives inside the overflow menu in
  both layouts, while Inútil Music also retains its direct shortcut beside
  Favorites. The Apple trigger keeps a 48 px touch target without applying that
  constraint to the popup route. Mobile Apple spacing now places the cover
  closer to the grabber and grows it responsively while preserving safe-area
  clearance, the non-scrolling short-phone layout, and landscape adaptation.
- Added an Animated artwork option under Appearance > Player, enabled by
  default for both new and existing installations. The large player cover uses
  independent closed loops for a 28-second zoom, 31-second 7 x 4 px pan, and
  35-second 3D drift capped at +/-0.3 degrees X, +/-0.4 degrees Y, and +/-0.12
  degrees Z with 0.00085 perspective. A viewport-aware crop guard prevents
  moving edges from becoming visible. Pausing playback freezes all motion at
  its current phase and resuming continues without a jump. It remains static
  for reduced motion, hidden player tabs, app backgrounding, missing artwork,
  or when the preference is disabled.
- Mobile Lyrics now morphs smoothly between its portrait header and landscape
  playback companion after the first stable rotation frame, while preserving
  the same lyrics scroll state. Its companion uses the same uniform linear
  Apple seek track without a thumb in every player style. Reduced-motion mode
  switches immediately, and the active Android lyric now keeps a clean white
  foreground with a mobile-compensated layered outer glow that remains as visible as desktop,
  without the former foreground shader or an additional render layer.
- Renamed the visible appearance labels to Liquid Glass Style and Flotante;
  their persisted `liquidGlass` and `capsule` values remain unchanged.
- Removed the former vendored extractor and companion resolver runtimes.
  Catalog access, playback, and downloads now use an in-process modular Dart
  InnerTube architecture on every platform, with one shared resolver for
  playback and downloads.
- Added maintained client profiles with correctness-first routing, deep ranged
  media validation, health cooldowns, latency tracking, and automatic fallback.
- Added independent EJS `s`/`n` challenge solving and Web BotGuard PO-token
  support through an isolated headless system WebView, with no custom Kotlin
  extractor or bundled resolver executable.
- Added page-specific dynamic player bootstrap, three independently validated
  tokenless profiles, an EJS-backed embedded fallback, anti-bot visitor/player
  PO escalation, fail-closed integrity tokens, alternate coherent attestation,
  and capability-level EJS/WebPO circuit breaking.
- Added raw/tokenless and full resolved client matrices. Raw gated clients are
  now reported as skipped instead of failed, and every success requires a deep
  or end-of-file CDN range probe. Strict resolved runs isolate state and enforce
  success thresholds per profile with separate cold/warm latency reporting.
- Downloads now prefer audio-only InnerTube formats, retain a validated muxed
  `.mp4` only as the last resort, and use a resumable `dart:io` transfer with
  strong representation validators, bounded retries, safe partial files, and
  atomic promotion.
- Linux release automation now isolates Ubuntu package sources from unrelated
  runner feeds, declares libsecret for builds and installed packages, and
  extracts both DEB and RPM outputs to validate their complete payloads.

## 1.2.5+125 — updated 2026-08-22

### Added

- Optional YouTube Music account sign-in with an isolated browser, encrypted
  on-device session storage, account/channel selection, a Home avatar, and an
  explicit warning that the integration is unofficial and unaffiliated with
  Google. Inútil Music never receives or stores the account password.
- Bidirectional local/YouTube Music playlist synchronization with stable IDs,
  occurrence-safe duplicates, private-by-default remote creation, three-way
  merging, bounded automatic retries, and explicit conflict review.
- A per-account first-sync confirmation keeps every local playlist untouched
  until the user explicitly chooses **Keep and sync**; choosing **Not now**
  performs no remote reads or writes and can be revisited from the account menu.
- Account-free Home personalization backed by qualified local listening
  history. Inútil Music combines YouTube Music `/next`, related shelves, generated
  mixes, and exact artist pages into **Because you listened**, **Your mixes**,
  **New for you**, and **Discovery for you** sections.
- Persistent anonymous InnerTube visitor data, related-result caches, and an
  instant stale-while-revalidate Home feed so recommendations survive restarts
  while still refreshing in the background.
- Privacy controls to pause recommendation learning or clear listening signals
  and personalized caches without deleting downloads, favorites, or playlists.
- A bounded InnerTube retry policy, crash-safe download-directory migration
  journal, playback-history retention, and CI security/size gates for release
  artifacts and dependencies.

### Improved

- Synced playlists can retain remote songs without downloading them. Playback
  prefers an available download and falls back to the matching stream, while
  imported artwork and metadata remain visible offline when locally cached.
- Playlist rows show a compact cloud before the artist only when no usable
  downloaded audio exists; cached artwork and empty files do not count as a
  download.
- Removing a synchronized playlist is local-only by default; deleting it from
  YouTube Music requires a separate confirmation and an editable playlist from
  the active account. Ambiguous writes are never blindly repeated.
- YouTube Music artist browse identifiers now survive search, playback,
  downloads, database migrations, and app restarts, allowing new-release
  recommendations to use exact artist identities instead of name guesses.
- Listening history now qualifies a play only after 40 percent or 30 seconds,
  whichever comes first, and covers both remote streams and catalog-backed
  downloads without counting seeks or accidental taps.
- Personalized AutoMix cards now load their real YouTube Music radio queue,
  and recommendation shelves remain navigable with Previous/Next even when
  downloaded and streaming entries appear together or start with one item.
- Active streams now retry the complete `youtube_explode_dart` → yt-dlp chain
  twice with bounded backoff after transient connection loss. Duplicate player
  errors share one retry budget, user navigation cancels stale attempts, and a
  terminal TikTok LIVE request advances to the next ready item without looping.
- Player playback, queue navigation, retry, prefetch, history, and crossfade
  responsibilities are split into focused coordinators instead of one
  3,600-line controller. Stale queue work and native option races are now
  generation-aware.
- Optional native services initialize after the first frame and retry only the
  failed integration. Japanese romanization loads its dictionary lazily from a
  compressed asset and releases the expanded worker after an idle timeout.
- Android runtime yt-dlp updates are stable-channel by default and must match
  the official release checksum and the version reported by the executable;
  invalid copies fall back to the bundled verified binary.
- Backup restore validates entry counts, individual and expanded sizes,
  compression ratio, duplicate paths, manifest, and SQLite schema before
  replacing active data.

### Fixed

- Mobile Lyrics no longer duplicates the mini-player; its header artwork acts
  as Back and the larger Play/Pause control remains reachable at narrow widths.
- The mini-player stays attached to bottom navigation when the software
  keyboard opens instead of retaining an extra system-navigation inset.
- Back from a player opened through a notification or launcher entry now
  returns to Home instead of closing the application; Queue retains its own
  nested Back behavior.

### Initial 1.2.5 release — 2026-08-20

#### Added

- Dual-deck crossfade playback on Android and desktop with a persistent,
  accessible whole-second duration control from 1 through 15 seconds.
- Optional lyrics romanization that keeps each original line above a smaller
  transliteration. Japanese, Korean, Chinese, Cyrillic, Arabic, and Hebrew can
  be selected independently and are represented in the live settings preview.
- Android EJS challenge solving through the bundled QuickJS runtime, optional
  BotGuard WebView PO-token generation, and a shared Deno solver on desktop for
  reinforced `youtube_explode_dart` requests.
- Desktop Space-key Play/Pause handling for both player surfaces while leaving
  Search and other focused editable fields untouched.

#### Improved

- YouTube audio resolution now follows a deterministic client ladder, retries
  solver-dependent clients only when needed, validates the exact selected
  stream, and reports every attempted client when direct resolution fails.
- Downloads try all reinforced `youtube_explode_dart` candidates before a
  single serialized yt-dlp fallback. Resolution and transfers use bounded
  deadlines, clean partial files, retain native containers, and avoid falling
  back for local filesystem failures.
- CSV restoration processes up to three tracks concurrently while keeping
  playlist membership and source order deterministic, reusing existing files,
  honoring cancellation, and continuing past individual failures.
- Japanese romanization uses token boundaries instead of arbitrary character
  chunks; paired original and romanized lyrics remain scrollable without
  overflow on narrow displays and large text scales.
- Full and mini-player layouts are denser and more consistent across Android
  and desktop, with clearer primary controls, closer timeline labels, safe CJK
  metadata wrapping, and a neutral accent-tinted desktop mini-player surface
  independent of the full-player artwork background.
- Library overview cards use the same larger artwork geometry as track-detail
  rows, Settings cards share compact spacing and surfaces, and the Windows
  playback queue uses more of the available width.
- Search title changes and expandable Crossfade settings use bounded accessible
  transitions, including reduced-motion behavior without layout jumps.
- Android hides the desktop-only download-folder control. CSV export profiles
  present only their compatibility names: Inútil Music, MetroList,
  Harmony/RiMusic, and Soundiiz.

#### Fixed

- Legacy no-animation lyrics preferences now migrate to Smooth, and the
  redundant play control was removed from the lyrics header on every platform.
- Crossfade preparation, promotion, seeks, pause/resume, Stop, disabling, and
  disposal are generation-aware so stale deck operations cannot replace the
  current song or leak a prepared player.
- Concurrent library downloads now coalesce identical tracks and publish one
  consistent local file instead of racing duplicate writes.
- Rapid tab changes no longer retain stale accessibility semantics nodes that
  could trigger Flutter AXTree update errors.
- Compact player artwork, multiline titles, timelines, and controls avoid the
  observed bottom and horizontal overflows on small Android screens.

## 1.2.4+124 — 2026-08-15

### Added

- Primary playback resolution and native-container downloads through
  `youtube_explode_dart`, with an explicit yt-dlp fallback for resolution,
  stream-validation, player-open, and download failures.
- Categorized InnerTube search for Songs, Videos, and Albums. Album, playlist,
  and mix results open a metadata and track-list page before playback creates
  the remote queue.
- Refreshable YouTube Music Home shelves with lazy collection lookups and
  bounded continuations of up to 100 detail tracks.
- CSV library import and export with Inútil Music, MetroList, Harmony/RiMusic,
  Soundiiz, Exportify, and common title/artist/album/ISRC layouts. Imports are
  previewed, deduplicated, confirmed, and downloaded sequentially.
- Native Dart TikTok LIVE support on Android, Windows, Linux, and macOS. LIVE
  requests can play remotely without entering the Library or be downloaded and
  saved first through a persistent setting.
- Four persistent lyrics animation styles with alignment controls and an
  interactive preview.
- Mobile multi-selection for downloaded songs and playlist contents, including
  batch add, remove, and delete actions.
- Android ARMv7 release artifacts alongside ARMv8 and x86_64 on the existing
  Android 7.0 baseline.
- Song sharing from the full player with one canonical HTTPS link recognized
  by chat applications. YouTube Music is preferred for InnerTube catalog
  tracks, while generic video results retain a regular YouTube watch URL.

### Improved

- YouTube Explode now uses isolated, mutable client payloads and starts with a
  current VisionOS client plus watch-page context. The exact selected audio URL
  is verified with a bounded byte-range request before reaching the player.
- Audio selection prefers the default audio track and compatible M4A/AAC,
  while retaining WebM/Opus and other available audio-only containers as
  fallbacks without transcoding.
- yt-dlp fallback playback uses bounded managed downloads, strict cache limits,
  latest-request-wins cancellation, inactivity and total deadlines, and active
  source protection during hand-off.
- Playback opens, errors, queue mutations, and source changes are generation
  aware on just_audio and MediaKit, preventing stale operations from replacing
  or blocking the current song.
- Search categories load on demand; yt-dlp discovery fallback is represented as
  Videos only. Search returns up to 20 results, and empty tabs disappear when
  the query is cleared.
- Song, Video, and Album search categories now use a short accessible
  cross-fade, while album, playlist, and mix details reuse their artwork as a
  bounded, contrast-safe blurred header background.
- Remote track rows in Search and album, playlist, and mix details now expose
  Play/Pause plus More actions for Download and Add to playlist without
  forcing the full player open.
- Home hides empty Recently played and local Playlist sections and can refresh
  remote recommendations without hiding existing local content.
- Settings uses denser shared cards, a language selection dialog, grouped
  Import and Export actions, persistent LIVE storage behavior, an Application
  information entry with an organized About detail for version, support, and
  the official GitHub repository, and eighteen accent palettes including Brown
  in place of Amber.
- Library, Home, Search, mini-player, and full-player layouts now use bounded
  artwork decoding, lazy lists, 48 dp controls, and adaptive measurements for
  320 x 568 displays at up to 300% text scaling.
- Download identity, coalescing, partial-file publication, progress, and
  rollback now remain consistent across search, playback, playlists,
  favorites, CSV imports, and LIVE requests.
- TikTok LIVE now filters ordinary chat before decoding full viewer profiles,
  acknowledges busy WebSocket batches before routing events, and resolves up
  to three music requests concurrently while committing the queue in original
  command order. A bounded search deadline prevents one stalled lookup from
  blocking the entire queue without cutting off an active download.
- Backup, restore, downloads, and migration share an operation coordinator so
  destructive storage work waits for active library commits.
- Final Android yt-dlp failures show the useful multiline extractor message
  directly instead of leading with the Java exception wrapper.
- Desktop installers no longer bundle the obsolete Python TikTok LIVE bridge;
  release validation rejects stale bridge artifacts and verifies all Android
  ABIs and bundled yt-dlp resources.
- Android and desktop keep up to three upcoming remote tracks prepared without
  restarting the current item; Android uses a rolling native media queue.
- Desktop remote playback uses a collision-resistant 12-hour application-cache
  LRU with 24-file, 256 MiB total, and 128 MiB per-track limits.
- Search artwork, lyrics, and player typography scale more consistently across
  compact and wide surfaces, while content and controls retain subtle
  accent-aware contrast in light and dark themes.

### Fixed

- Fixed an iOS Explode attempt that always failed when the package tried to add
  `visitorData` to an immutable nested payload.
- Fixed Quick picks without catalog duration losing the duration detected by
  ExoPlayer, which left the timeline at `--:--` and disabled seeking.
- Fixed manifests being accepted after validating a different stream than the
  AAC/WebM URL actually selected for playback.
- Fixed late backend errors, reversed asynchronous opens, and queue updates
  being attributed to a newer track.
- Fixed managed fallback pruning that could remove the source still being
  played while preparing its replacement.
- Fixed concurrent desktop cache publishers producing inconsistent entries for
  the same source across processes.
- Fixed duplicate local filenames and IDs for distinct tracks sharing artist
  and title metadata.
- Fixed failed database persistence leaving newly downloaded audio or thumbnail
  artifacts behind.
- Fixed player, timeline, mini-player, navigation, and LIVE queue overflows on
  narrow windows and large accessibility text sizes.

## 1.2.3+123 — 2026-08-09

### Added

- Android `Open with` support for local audio, including a folder-backed queue
  when media-library access and provider metadata are available.
- System, Light, and Dark themes with nine persistent accent palettes.
- Long-press queue reordering that preserves the active track and synchronizes
  Android's native media queue.
- Controlled preloading of only the next remote track.
- Song-count and total-duration summaries for playlists and downloaded songs.
- An inline search clear button that appears only while the field has text.
- A localized support section in Settings with a direct Ko-fi contribution
  link; the app remains free.

### Improved

- Unified high-quality artwork selection and proportional cropping across
  search, playback, playlists, downloads, and older YouTube thumbnails.
- Search now returns up to 15 results on Android and desktop.
- Accent-aware gradients, tabs, progress bars, lyrics, cards, menus, and player
  controls in both light and dark themes.
- Android remote playback with earlier source validation, preserved request
  headers, selective extractor updates, one retry, clearer HTTP/format errors,
  and restoration of the bundled extractor after a failed update retry.
- Android APK builds now bundle checksum-verified stable yt-dlp `2026.07.04`,
  matching the desktop release version. Existing installations migrate older
  bundled copies while preserving an equal or newer downloaded update.
- Long-session resource use with bounded artwork, thumbnail, remote-audio, and
  LRCLIB caches, request limits, and reduced position-update work.
- Backup restore validation for manifests, archive paths and limits, SQLite
  integrity, schema, and version, followed by staged activation and rollback.
- Recent playback retains its playlist context and queue changes remain aligned
  with native media controls.
- Release automation runs formatting, analysis, and tests before packaging and
  verifies the yt-dlp resource inside both Android APKs.

### Fixed

- Cancelling the custom sleep-timer dialog no longer raises an error.
- Artwork no longer changes crop or stretches after remote extraction or after
  saving a previously played track.
- Light-theme player buttons, contextual menus, lyrics controls, translucent
  surfaces, and accent contrast use theme-appropriate colors.
- The download status strip above the mini player was removed in favor of the
  integrated progress presentation.
- Back-button sizing, playlist navigation, old-thumbnail fallbacks, and several
  player layout inconsistencies were corrected.
