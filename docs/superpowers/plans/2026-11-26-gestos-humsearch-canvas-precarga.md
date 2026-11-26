# Gestos, Búsqueda Acústica, Canvas Cinemático y Precarga Instantánea Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar en Inutix Music gestos táctiles fluidos en el reproductor a pantalla completa, búsqueda por tarareo/canto/voz ("Di, canta o tararea") con ondas neón integradas, sustitución completa de `spotycovs.lol` por Canvas Generativo Líquido en GPU con video loops de YouTube, y precarga en segundo plano de audio y Canvas para reproducción con 0 ms de latencia.

**Architecture:** Módulo de gestos interactivos desacoplado (`PlayerGesturesWrapper`), hoja modal de captura acústica (`HumSearchSheet`) conectada al resolver InnerTube de audio, motor de renderizado de gradientes en GPU (`GenerativeMeshCanvas`) como reemplazo autónomo de `spotycovs.lol`, y coordinador de precarga en segundo plano (`PlaybackPreloadCoordinator`) integrado en el ciclo de vida de `JustAudioPlayerService`.

**Tech Stack:** Flutter, Dart, Riverpod, Just Audio (`AudioSource` pre-buffering), `CustomPainter` con gradientes radiales dinámicos, InnerTube API (audio search).

**Spec:** [docs/superpowers/specs/2026-11-26-gestos-humsearch-canvas-precarga-design.md](file:///home/cesar/Escritorio/alo/inutil_music/docs/superpowers/specs/2026-11-26-gestos-humsearch-canvas-precarga-design.md)

## Global Constraints

- **Paleta de color estricta:** Fondo carbón profundo (`#0A0B10`), superficie elevada (`#141622`), acentos cian neón (`#00E5FF`) y violeta eléctrico (`#7C4DFF`). Prohibidos fondos blancos lechosos o estilos ajenos a la app.
- **Cero servicios comerciales de pago:** Ninguna dependencia de ACRCloud, Shazam API o similares. Cero costo de operación.
- **Erradicación de `spotycovs.lol`:** Ninguna llamada a scrapers caídos o no oficiales de terceros.
- **Compatibilidad Android:** Android 7.0 a Android 15 (API 24 a 35), optimizado para procesadores de 64 bits (ARM64) y 32 bits (ARMv7).
- **Rendimiento de interfaz:** 60 fps estables durante arrastres y animaciones de canvas; la precarga de audio nunca debe bloquear el isolate principal.

## Review Focus

1. **Ruido ambiental o silencio en la búsqueda acústica:** Si el usuario presiona el micrófono pero no emite sonido o hay ruido excesivo, la hoja debe indicar amablemente «No pudimos identificar la canción. Intenta de nuevo» con botón de reintentar sin congelar la interfaz.
2. **Arrastre diagonal o no intencionado en el reproductor:** Un scroll vertical para ver la letra o la cola no debe disparar por error el cambio horizontal de pista ni el salto de 10 segundos.
3. **Pistas sin conexión a internet en la precarga:** Si la red se cae o es inestable durante la reproducción, la precarga de la pista `N+1` debe fallar silenciosamente sin interrumpir la pista `N` que está sonando.
4. **Colisiones de colores en Canvas Generativo:** Si la carátula es completamente negra, monocromática o blanca, el generador de gradientes debe asegurar contraste suficiente para que los controles y textos sigan siendo 100 % legibles.
5. **Doble tap rápido continuo:** Múltiples toques rápidos dobles deben acumular el salto de tiempo (+10s, +20s, +30s) en lugar de reiniciar el estado y provocar saltos bruscos de audio.

---

### Task 1: Búsqueda Acústica ("Di, canta o tararea") y UI Neón Integrada

**Files:**
- Create: `lib/services/youtube_music/search/innertube_audio_search_service.dart`
- Create: `lib/features/music/presentation/widgets/hum_search_sheet.dart`
- Modify: `lib/features/music/presentation/pages/search_page.dart:180-260`
- Test: `test/features/music/presentation/widgets/hum_search_sheet_test.dart`

**Interfaces:**
- Consumes: `AppColors`, `InutilDesignSystem`, `Song` model, `ref.read(playerProvider)`.
- Exposes: `showHumSearchSheet(BuildContext context)`, `InnertubeAudioSearchService.searchByAudio(List<int> audioData)`.

- [ ] **Step 1: Escribir prueba unitaria para `HumSearchSheet` y servicio de búsqueda acústica**

Crear `test/features/music/presentation/widgets/hum_search_sheet_test.dart` verificando:
1. El texto principal muestra exactamente: «Di, canta o tararea un fragmento de la canción».
2. La paleta de colores utiliza los valores de `AppColors.backgroundDark` y los tonos neón `#00E5FF` / `#7C4DFF`.
3. Estados de la interfaz: `Escuchando...`, `Buscando coincidencias...` y lista de resultados.

- [ ] **Step 2: Ejecutar prueba y verificar que falle (Red)**

Run: `cd /home/cesar/Escritorio/alo/inutil_music && flutter test test/features/music/presentation/widgets/hum_search_sheet_test.dart`  
Expected: FAIL (archivos aún no existen).

- [ ] **Step 3: Implementar `InnertubeAudioSearchService`**

Crear `lib/services/youtube_music/search/innertube_audio_search_service.dart` con el método:
```dart
Future<List<Song>> searchByAudio(List<int> audioBytes);
```
Que utiliza la sesión anónima de InnerTube para resolver coincidencias de audio/melodía y transformarlas a objetos `Song`.

- [ ] **Step 4: Implementar `HumSearchSheet` y conectar el botón en `SearchPage`**

1. Crear `lib/features/music/presentation/widgets/hum_search_sheet.dart` con visualizador de ondas reactivo en GPU, animación de pulso y selección de resultados.
2. En `lib/features/music/presentation/pages/search_page.dart`, agregar el icono de onda sonora en el campo de texto que invoca `showHumSearchSheet(context)`.

- [ ] **Step 5: Ejecutar pruebas y verificar éxito (Green)**

Run: `cd /home/cesar/Escritorio/alo/inutil_music && flutter test test/features/music/presentation/widgets/hum_search_sheet_test.dart`  
Expected: PASS.

- [ ] **Step 6: Commit de Task 1**

```bash
git add lib/services/youtube_music/search/innertube_audio_search_service.dart lib/features/music/presentation/widgets/hum_search_sheet.dart lib/features/music/presentation/pages/search_page.dart test/features/music/presentation/widgets/hum_search_sheet_test.dart
git commit -m "feat(search): búsqueda acústica con InnerTube ('Di, canta o tararea') y UI neón reactiva"
```

---

### Task 2: Sistema de Gestos en Reproductor a Pantalla Completa

**Files:**
- Create: `lib/features/music/presentation/widgets/player_gestures_wrapper.dart`
- Create: `lib/features/music/presentation/widgets/double_tap_seek_ripple.dart`
- Modify: `lib/features/music/presentation/widgets/player_panel.dart:1200-1350`
- Modify: `lib/features/music/presentation/widgets/spotify_fullscreen_canvas_player.dart:250-380`
- Test: `test/features/music/presentation/widgets/player_gestures_wrapper_test.dart`

**Interfaces:**
- Consumes: `ref.read(playerProvider).next()`, `ref.read(playerProvider).previous()`, `ref.read(playerProvider).seekTo()`, `onOpenLyrics()`.
- Exposes: `PlayerGesturesWrapper` widget envolvente con soporte para swipe horizontal (con umbral de inercia), swipe vertical hacia abajo para minimizar, swipe vertical hacia arriba para abrir la letra en vivo, doble tap para salto acumulativo ±10s y deslizadores laterales de volumen/brillo.

- [ ] **Step 1: Escribir pruebas unitarias para `PlayerGesturesWrapper` y `DoubleTapSeekRipple`**

Crear `test/features/music/presentation/widgets/player_gestures_wrapper_test.dart` verificando:
1. Swipe a la izquierda dispara callback `onNext`.
2. Swipe a la derecha dispara callback `onPrevious`.
3. Swipe hacia abajo con desplazamiento > 120 px dispara `onMinimize`.
4. Swipe hacia arriba con desplazamiento > 100 px dispara `onOpenLyrics`.
5. Doble tap en borde derecho dispara `onSeekForward(10)`.
6. Doble tap en borde izquierdo dispara `onSeekBackward(10)`.
7. Toques continuos rápidos acumulan los segundos (+10s, +20s, +30s).

- [ ] **Step 2: Ejecutar prueba y verificar que falle (Red)**

Run: `cd /home/cesar/Escritorio/alo/inutil_music && flutter test test/features/music/presentation/widgets/player_gestures_wrapper_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implementar `DoubleTapSeekRipple` y `PlayerGesturesWrapper`**

1. Crear `double_tap_seek_ripple.dart` con animación de ondas cian neón y contador numérico `+10s` / `-10s`.
2. Crear `player_gestures_wrapper.dart` manejando `onHorizontalDragUpdate`, `onHorizontalDragEnd`, `onVerticalDragUpdate`, `onDoubleTapDown` con umbral de rechazo angular (evita disparos en scroll diagonal).

- [ ] **Step 4: Integrar el envoltorio en `player_panel.dart` y `spotify_fullscreen_canvas_player.dart`**

Envolver el área de carátula y lienzo con `PlayerGesturesWrapper`, conectando las acciones a los controladores de `playerProvider`.

- [ ] **Step 5: Ejecutar pruebas y verificar éxito (Green)**

Run: `cd /home/cesar/Escritorio/alo/inutil_music && flutter test test/features/music/presentation/widgets/player_gestures_wrapper_test.dart`  
Expected: PASS.

- [ ] **Step 6: Commit de Task 2**

```bash
git add lib/features/music/presentation/widgets/player_gestures_wrapper.dart lib/features/music/presentation/widgets/double_tap_seek_ripple.dart lib/features/music/presentation/widgets/player_panel.dart lib/features/music/presentation/widgets/spotify_fullscreen_canvas_player.dart test/features/music/presentation/widgets/player_gestures_wrapper_test.dart
git commit -m "feat(player): gestos táctiles completos (swipe pista, swipe minimizar, doble tap ±10s y sliders)"
```

---

### Task 3: Sustitución de `spotycovs.lol` por Canvas Cinemático Generativo en GPU

**Files:**
- Create: `lib/features/music/presentation/widgets/generative_mesh_canvas.dart`
- Modify: `lib/services/spotify_canvas/spotify_canvas_resolver.dart:1-220`
- Modify: `lib/features/music/presentation/widgets/inutil_canvas_engine.dart:40-120`
- Modify: `lib/features/music/presentation/widgets/spotify_fullscreen_canvas_player.dart:180-260`
- Test: `test/features/music/presentation/widgets/generative_mesh_canvas_test.dart`

**Interfaces:**
- Consumes: Carátula de la pista (`ImageProvider`), estado de reproducción (`isPlaying`), paleta de colores.
- Exposes: `GenerativeMeshCanvas` que renderiza malla de gradientes líquidos orgánicos continuos con cero consumo de red y 100 % de cobertura.

- [ ] **Step 1: Escribir pruebas unitarias para `GenerativeMeshCanvas` y eliminación de scrapers**

Crear `test/features/music/presentation/widgets/generative_mesh_canvas_test.dart` verificando:
1. `SpotifyCanvasResolver` ya no contiene ninguna referencia a `spotycovs.lol`.
2. Para cualquier carátula, `GenerativeMeshCanvas` genera colores armónicos contrastados y nunca se queda en negro.
3. Se valida el fallback a video loops oficiales de YouTube cuando exista `videoId`.

- [ ] **Step 2: Ejecutar prueba y verificar que falle (Red)**

Run: `cd /home/cesar/Escritorio/alo/inutil_music && flutter test test/features/music/presentation/widgets/generative_mesh_canvas_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implementar `GenerativeMeshCanvas` en GPU**

Crear `generative_mesh_canvas.dart` con `CustomPainter` optimizado en hardware:
* Malla de 4 nodos de color fluidos calculados a partir de la portada de la canción.
* Movimiento sinusoidal suave de baja tasa de cálculo con micro-pulsación al compás del audio.
* Partículas flotantes sutiles con estética Inutix.

- [ ] **Step 4: Limpiar `spotify_canvas_resolver.dart` e integrar el nuevo motor**

1. Purgar todas las llamadas HTTP a `www.spotycovs.lol`.
2. Integrar `GenerativeMeshCanvas` como capa primaria de fondo en `spotify_fullscreen_canvas_player.dart` y `inutil_canvas_engine.dart`, con soporte de video loops de YouTube si el clip oficial está disponible.

- [ ] **Step 5: Ejecutar pruebas y verificar éxito (Green)**

Run: `cd /home/cesar/Escritorio/alo/inutil_music && flutter test test/features/music/presentation/widgets/generative_mesh_canvas_test.dart`  
Expected: PASS.

- [ ] **Step 6: Commit de Task 3**

```bash
git add lib/features/music/presentation/widgets/generative_mesh_canvas.dart lib/services/spotify_canvas/spotify_canvas_resolver.dart lib/features/music/presentation/widgets/inutil_canvas_engine.dart lib/features/music/presentation/widgets/spotify_fullscreen_canvas_player.dart test/features/music/presentation/widgets/generative_mesh_canvas_test.dart
git commit -m "feat(canvas): eliminación de spotycovs.lol y nuevo Canvas Generativo Líquido en GPU con loops de YouTube"
```

---

### Task 4: Motor de Precarga Instantánea de Audio y Canvas (Zero-Latency Playback)

**Files:**
- Create: `lib/services/player/playback_preload_coordinator.dart`
- Modify: `lib/services/player/just_audio_player_service.dart:820-910`
- Modify: `lib/features/music/presentation/providers/player/player_playback_coordinators.dart:40-120`
- Test: `test/services/player/playback_preload_coordinator_test.dart`

**Interfaces:**
- Consumes: Cola de reproducción activa (`queue`), índice actual (`currentIndex`), cliente InnerTube.
- Exposes: `PlaybackPreloadCoordinator.preloadNext(QueueItem nextItem)`, precarga de los primeros 512 KB a 1 MB de audio y precalentamiento de Canvas.

- [ ] **Step 1: Escribir pruebas unitarias para `PlaybackPreloadCoordinator`**

Crear `test/services/player/playback_preload_coordinator_test.dart` verificando:
1. Al reproducir la pista `N`, se detecta la pista `N+1` y se agenda la precarga sin bloquear la reproducción.
2. Si la pista actual cambia, se cancelan las precargas obsoletas para ahorrar ancho de banda.
3. Si la conexión falla durante la precarga, el reproductor actual sigue funcionando con normalidad.

- [ ] **Step 2: Ejecutar prueba y verificar que falle (Red)**

Run: `cd /home/cesar/Escritorio/alo/inutil_music && flutter test test/services/player/playback_preload_coordinator_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implementar `PlaybackPreloadCoordinator`**

Crear `lib/services/player/playback_preload_coordinator.dart` con gestión de cola en segundo plano, descarga en caché local de búfer inicial y resolución temprana de URL.

- [ ] **Step 4: Integrar en `JustAudioPlayerService` y coordinadores de reproducción**

Conectar el precargador al evento de inicio de reproducción para precalentar `N+1`, de modo que al avanzar la pista el inicio sea inmediato en 0 ms.

- [ ] **Step 5: Ejecutar pruebas y verificar éxito (Green)**

Run: `cd /home/cesar/Escritorio/alo/inutil_music && flutter test test/services/player/playback_preload_coordinator_test.dart`  
Expected: PASS.

- [ ] **Step 6: Commit de Task 4**

```bash
git add lib/services/player/playback_preload_coordinator.dart lib/services/player/just_audio_player_service.dart lib/features/music/presentation/providers/player/player_playback_coordinators.dart test/services/player/playback_preload_coordinator_test.dart
git commit -m "feat(playback): precarga en segundo plano de audio y Canvas para reproducción con latencia 0 ms"
```

---

### Task 5: Validación Integral, Pruebas en Dispositivo y Limpieza

**Files:**
- Modify: `lib/core/constants/app_constants.dart`
- Modify: `pubspec.yaml`
- Modify: `CHANGELOG.md`
- Test: `test/core/constants/app_metadata_test.dart`
- Test: Todo el conjunto de pruebas del proyecto (`flutter test`)

- [ ] **Step 1: Ejecutar la suite completa de pruebas de regresión**

Run: `cd /home/cesar/Escritorio/alo/inutil_music && flutter test`  
Expected: Todos los tests deben pasar (0 fallos).

- [ ] **Step 2: Verificación de compilación en Android**

Run: `cd /home/cesar/Escritorio/alo/inutil_music && flutter build apk --release --split-per-abi --dart-define=FB_CLOUD_RELAY_HOST=api.inutix.com`  
Expected: Compilación exitosa de APKs de producción.

- [ ] **Step 3: Verificación en vivo en dispositivo conectado Xiaomi 12 Pro (`a586e98a`)**

Instalar y comprobar con `adb`:
1. Abrir búsqueda y verificar la hoja «Di, canta o tararea» con ondas neón.
2. Abrir reproductor y verificar gestos táctiles (swipe horizontal, swipe abajo y doble tap ±10s).
3. Verificar Canvas Líquido continuo sin fallos de `spotycovs.lol`.
4. Verificar cambio de pista con precarga instantánea.

- [ ] **Step 4: Commit y push final**

```bash
git commit -am "chore: validación integral y estabilización de nuevas funciones en Inutix Music"
git push origin master
```
