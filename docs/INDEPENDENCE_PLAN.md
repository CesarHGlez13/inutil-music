# Plan paso a paso hacia código 100 % propio (Inútil Music)

Este documento define con exactitud:
1. **Qué pertenece hoy a Bryam Contreras**, qué pertenece **100 % a Inútil Music** y qué pertenece a **otros terceros**.
2. **Las reglas técnicas y legales obligatorias** para sustituir todo el código heredado sin problemas legales ni regresiones en producción.
3. **El plan incremental por fases (Fases 0 a 7)** para llevar cada subsistema a implementación propia limpia (*clean-room*).

---

## 1. Inventario exacto de titularidad actual

Medición verificada sobre el árbol actual (`v2.5.6+256`):

### A. Propiedad exclusiva de Inútil Music (`Copyright (c) 2026, Inútil Music`)

| Bloque | Rutas principales | Volumen aproximado |
| :--- | :--- | :--- |
| **Firebase, Auth, Cloud Backup, Admin y OTA** | `lib/core/firebase/*`, `firebase/*`, `lib/services/app_update/*` | `16` archivos Dart (`~8,876` L) + reglas Firestore |
| **Tema, iconografía y marca propia** | `lib/core/theme/inutil_design_system.dart`, `inutil_icons.dart`, `inutil_logo.dart`, `assets/icons/*`, `ic_stat_inutil_music.png`, mipmaps/icons | `~840` L Dart + todos los assets gráficos |
| **Módulos UI y flujos nuevos** | `inutil_admin_panel.dart`, `inutil_spotify_import_dialog.dart`, `inutil_onboarding_tour.dart`, `inutil_wrapped_dialog.dart`, `inutil_account_dialog.dart`, `inutil_connect_sheet.dart`, `inutil_support_popup.dart`, `inutil_sleep_timer_sheet.dart`, `spotify_fullscreen_canvas_player.dart`, `video_preview_reel_sheet.dart`, `inutil_canvas_engine.dart` | `13` archivos Dart (`~8,610` L) |
| **Motor de previews de video y utilidades** | `lib/services/video_preview/video_preview_resolver.dart`, `video_preview_provider.dart`, `inutil_track_link.dart`, `release_paths.dart` | `~569` L Dart |
| **Nativo Android nuevo y adaptaciones propias** | `InutilCanvasEnginePlugin.kt`, `provider_paths.xml`, layouts/drawables propios, `linux/runner/main.cc` (Mesa EGL), `tool/*`, `.github/workflows/*` | Nativo + CI/CD + empaquetado |

### B. Código base bajo BSD 2-Clause (`Copyright (c) 2026, Bryam Contreras`)

- **`lib/` (Dart):** `375` archivos compartidos con el repositorio base (`262` sin modificaciones y `113` con adaptaciones; `160,676` líneas idénticas de `183,291` totales, es decir **`87.7 %`**).
  - `features/music/presentation/` (`146` archivos base / `~86,556` L)
  - `services/youtube_music/` (`53` archivos / `~26,087` L)
  - `services/player/` (`12` archivos / `~9,184` L)
  - `services/storage/` (`11` archivos / `~7,189` L)
  - `services/downloader/` (`15` archivos / `~5,628` L)
  - `services/lyrics/` (`15` archivos / `~5,620` L)
  - `core/widgets/` (`7` archivos / `~3,520` L)
  - `services/live/` (`5` archivos / `~2,714` L), `services/recommendations/` (`6` / `~1,904` L), `services/casting/` (`4` / `~1,902` L), `features/music/data/` + `domain/` (`38` / `~2,900` L), `services/jiosaavn/`, `services/audio_sources/`, `services/local_media/`, `services/media_session/`, `platform_channels/`, `core/startup/`, `core/animation/`.
- **Nativo heredado/adaptado:** clases portadas desde el paquete original en `android/app/src/main/kotlin/com/inutilmusic/app/` (por ejemplo `MainActivity.kt`, `InutilMusicWidget.kt`, `InutilCastPlugin.kt`, `AudioOutputPlugin.kt`, etc.), `ios/Runner/`, `ios/NowPlayingWidget/`, `macos/Runner/`, `windows/runner/` y base GTK de `linux/runner/`.

### C. Terceros externos independientes (no de Bryam)

Documentados íntegramente en [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md):
- `just_audio` 0.10.6 (fork local en `third_party/just_audio/`, **MIT** + ExoPlayer/Media3 **Apache-2.0**)
- `Kyant AndroidLiquidGlass` (`shaders/liquid_glass_refraction.frag`, **Apache-2.0**)
- `piratetok_live` (`third_party/piratetok_live/`, **0BSD**)
- `EJS` 0.8.0 (`The Unlicense`, con `meriyah` **ISC** y `astring` **MIT**)
- `csv`, `xml` (**MIT**), SDKs de Google Cast, Flutter y dependencias de `pubspec.yaml`

---

## 2. Reglas innegociables para evitar fallos técnicos y problemas legales

1. **Regla legal (*clean-room* real, cero parafraseo):**
   - Renombrar clases, mover líneas o reescribir un archivo leyendo el original **no** elimina los derechos de autor de una obra derivada.
   - Para que cada nuevo módulo sea 100 % propio: primero se redacta una **especificación funcional y de pruebas** (qué entra, qué sale, qué errores maneja), y luego se implementa desde cero en un archivo/paquete limpio **sin copiar código ni estructura interna** del archivo anterior.
2. **Regla de licencia durante la transición:**
   - **Prohibido retirar** `Copyright (c) 2026, Bryam Contreras` de `LICENSE` o `THIRD_PARTY_NOTICES.md` mientras quede **al menos 1 archivo heredado** en el repositorio.
   - Solo al terminar la **Fase 7** (0 líneas heredadas) el código nuevo pasa a licenciarse exclusivamente bajo los términos que elija Inútil Music (manteniendo únicamente los avisos de terceros externos como Flutter, `just_audio`, `media_kit`, `sqflite`, `AndroidLiquidGlass`, etc.).
3. **Regla de estabilidad (*zero-downtime*, *strangler pattern*):**
   - Nunca se rompe la app principal ni los datos del usuario: el módulo nuevo convive detrás de una **interfaz/contrato** y debe igualar o superar los tests de regresión, migraciones SQLite y pruebas reales en Android/Linux antes de desconectar y borrar el módulo heredado.

---

## 3. Plan de ejecución paso a paso (Fases 0 a 7)

### Fase 0 — Congelación de contratos y red de seguridad
- **Objetivo:** aislar dependencias para poder reemplazar pieza por pieza sin romper nada.
- **Acciones:**
  1. Definir contratos limpios en `lib/core/contracts/` (por ejemplo `LibraryStore`, `MediaResolver`, `PlaybackEngine`, `LyricsFetcher`, `DownloadQueue`, `LocalScanner`, `CastController`).
  2. Asegurar que todos los módulos propios (`core/firebase/*`, `app_update/*`, `InutilTheme`, `video_preview/*`) dependan únicamente de esos contratos, nunca de implementaciones heredadas concretas.
  3. Congelar pruebas de integración/regresión que validen apertura de `inutil_music.db` existente, restauración Cloud Backup, reproducción, importación Spotify y actualización OTA.
- **Criterio de salida:** CI/tests verdes y cero acoplamientos circulares hacia nuestros módulos propios.

### Fase 1 — Dominio, Almacenamiento SQLite, CSV y Biblioteca Local
*(Reemplaza `features/music/domain/`, `features/music/data/`, `services/storage/`, `services/local_media/`, `services/sharing/`)*
- **Objetivo:** ser dueños absolutos de los modelos de datos, esquema SQLite y lectura de archivos locales.
- **Acciones:**
  1. Diseñar modelos propios inmutables (`Track`, `Playlist`, `LibraryEntry`) y repositorio propio sobre `sqflite` / `sqflite_common_ffi` manteniendo compatibilidad 100 % con las tablas/columnas existentes de `inutil_music.db` (`inutil:favorites`, `local_tracks`, `playlists`, `playlist_items`, `library_track_order`).
  2. Escribir desde cero nuestro motor de importación/exportación CSV (`InutilCsvVersion` + perfiles interoperables) y escáner local Android/Desktop.
  3. Validar migración automática desde bases reales de usuarios v2.5.x sin pérdida de canciones ni playlists.
- **Criterio de salida:** módulo antiguo de `storage`/`domain`/`data`/`local_media` borrado; pruebas de migración SQLite, CSV y Cloud Backup al 100 %.

### Fase 2 — Servicios autónomos (Letras, Descargador, Recomendaciones y Matching)
*(Reemplaza `services/lyrics/`, `services/downloader/`, `services/recommendations/`, `services/jiosaavn/`, `services/audio_sources/`)*
- **Objetivo:** sustituir las piezas con menos acoplamiento a la UI.
- **Acciones:**
  1. Reescribir cliente HTTP unificado con caché memoria/disco para proveedores públicos de letras (LRCLIB, LyricsPlus, Better Lyrics) y parser propio LRC/TTML con temporización por palabra.
  2. Reescribir cola de descargas por streaming HTTP con reanudación por rango, etiquetado de metadatos y guardado de carátulas en `Inutil-Music/`.
  3. Implementar motor propio de scoring/similitud (el motor de importación Spotify y recomendaciones locales) con su batería de pruebas deterministas.
- **Criterio de salida:** descargas offline, letras sincronizadas e importación de Spotify funcionando sin ningún archivo heredado en estas carpetas.

### Fase 3 — Resolutor multimedia y sincronización de catálogo
*(Reemplaza `services/youtube_music/`)*
- **Objetivo:** contar con un pipeline InnerTube/catálogo 100 % diseñado por Inútil Music.
- **Acciones:**
  1. Documentar los contratos de búsqueda, stream audio, carátulas, cuenta y playlists a partir de los requisitos del producto.
  2. Implementar cliente HTTP/protocolo nuevo desde cero (sesión segura, rotación de perfiles de cliente, resolución de streams adaptativos, consumo verificado por SHA-256 de `EJS` si se mantiene) y motor propio de sincronización de playlists/Favoritos (`inutil:favorites`).
  3. Verificar playback continuo, búsqueda rápida, login embebido y sync bidireccional en pruebas reales en Android y Linux.
- **Criterio de salida:** carpeta heredada `youtube_music/` eliminada por completo.

### Fase 4 — Motor de audio/video, Sesión del sistema, Casting y LIVE
*(Reemplaza `services/player/`, `services/media_session/`, `services/casting/`, `services/live/`, `services/animated_artwork/`, `services/spotify_canvas/`)*
- **Objetivo:** controlar por completo el corazón multimedia de la app.
- **Acciones:**
  1. Escribir desde cero el controlador de cola, pre-buffer, crossfade, replay-gain/ecualizador y salto de silencio sobre `media_kit` (desktop/iOS) y Media3/`just_audio` (Android), manteniendo separado el motor de video (`video_preview`) para nunca causar micro-tirones de audio.
  2. Implementar integraciones propias MPRIS/SMTC/MediaSession, servidor HTTP/WebSocket local LAN para overlays y receptor LIVE (conectado a `piratetok_live` / SDKs propios), y controlador UPnP/Cast.
- **Criterio de salida:** reproducción en segundo plano, notificaciones/controles bloqueados, crossfade, LAN y Cast verificados en hardware real.

### Fase 5 — Interfaz completa de usuario (`UI` 100 % Inútil Music)
*(Reemplaza `features/music/presentation/`, `core/widgets/`, `core/animation/`, `core/startup/`, `main.dart`)*
- **Objetivo:** construir la interfaz definitiva de Inútil Music sobre `InutilTheme`, `InutilDesignSystem` e `InutilGlyph`.
- **Acciones:**
  1. Migrar pantalla por pantalla (`Shell/Navegación`, `Inicio`, `Buscar`, `Local`, `Biblioteca`, `Reproductor + MiniPlayer`, `Ajustes`) en Widgets limpios conectados a los contratos de las Fases 1–4 y a nuestros flujos propios (`inutil_auth_gate`, `inutil_admin_panel`, `inutil_update_*`, `inutil_wrapped_*`).
  2. Eliminar todo widget/código heredado en `presentation/` y `core/widgets/`.
- **Criterio de salida:** toda la app compilada con 0 archivos Dart heredados en `lib/`.

### Fase 6 — Capas nativas (`Android`, `Linux`, `Windows`, `iOS`, `macOS`)
*(Reemplaza clases portadas en `android/`, `linux/`, `windows/`, `ios/`, `macos/`)*
- **Objetivo:** eliminar las clases nativas que venían renombradas del paquete base.
- **Acciones:**
  1. Reescribir limpiamente por plataforma empezando por las usadas activamente (`Android` → `Linux` → `Windows` → `iOS/macOS`): `MainActivity` y intents, Home Screen widgets, selector de salida/calidad de audio, puente de ventana GTK/X11/Wayland y Win32.
  2. Verificar firma APK, `_NET_WM_ICON`, centrado/Mesa EGL en Linux NVIDIA y compilación de cada runner.
- **Criterio de salida:** ningún archivo fuente nativo heredado en el árbol.

### Fase 7 — Auditoría de pureza y cambio definitivo de licencia
- **Objetivo:** certificar que el repositorio es 100 % obra propia antes de retirar el copyright anterior.
- **Acciones:**
  1. Crear/consolidar el árbol final verificado sin ningún archivo ni bloque copiado del repositorio original (`0` coincidencias estructurales heredadas en `lib/`, plataformas y `test/`).
  2. Actualizar `LICENSE` al copyright exclusivo de Inútil Music (con la licencia que tú elijas: propietaria/All Rights Reserved o la que decidas).
  3. Actualizar `THIRD_PARTY_NOTICES.md` retirando la sección de base heredada y conservando únicamente las librerías externas reales que sigas usando (`Flutter`, `media_kit`, `sqflite`, `AndroidLiquidGlass`, `just_audio` si sigue usándose, `EJS`, `piratetok_live`, Google Cast).

---

## 4. Orden recomendado si vamos poco a poco sin prisa

Para avanzar de manera segura entre versiones normales de Inútil Music (por ejemplo en rama paralela o releases `2.x` → `3.0`):
1. **Fase 0 → Fase 1** (datos seguros primero, 0 impacto visual mientras madura).
2. **Fase 2** (servicios independientes fáciles de probar con tests unitarios).
3. **Fase 3** (InnerTube y sync de YouTube Music).
4. **Fase 4** (motor de audio/video/casting).
5. **Fase 5 → Fase 6 → Fase 7** (UI unificada, nativos limpios y corte final a la nueva base 100 % propia en una versión mayor **`3.0.0`**).
