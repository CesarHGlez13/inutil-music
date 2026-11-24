# Diseño: Compartir Momento (Mini Clips HD "tipo iPhone")

**Fecha:** 2026-11-24  
**Versión objetivo:** Inútil Music (Android nativo con arquitectura extensible multiplataforma)

## 1. Propósito y Experiencia de Usuario

Permitir que el usuario genere y comparta **mini clips verticales 9:16 de alta calidad ("tipo iPhone")** listos para WhatsApp HD, Estados, Instagram Reels/Stories y TikTok **sin requerir permisos de grabación de pantalla (`MediaProjection`) ni almacenamiento amplio**, accesibles desde ambas pantallas principales:

1. **Pantalla de Letras (`lyrics_page.dart`)**:
   - Menú de opciones (ícono de engrane) mantiene **"Compartir letras"** (tarjeta PNG estática) y agrega **"Compartir momento"** (clip MP4 HD en modo Letras).
2. **Reproductor a Pantalla Completa (`spotify_fullscreen_canvas_player.dart` y menú `...` de `player_panel.dart`)**:
   - Al tocar el botón de compartir (`Icons.share_outlined`) se presenta un menú compacto con **ambas opciones**: **"Compartir momento"** (clip MP4 HD en modo Reproductor) y **"Compartir canción"** (enlace). También accesible desde el menú `...`.

### Selector de momento (Modal `MomentShareSheet`)
- Vista previa 9:16 limpia (sin barras del sistema ni botones intrusivos) con selector de estilo (**Letras** / **Reproductor**) y **marca de agua translúcida sutil con el logo de Inútil Music** (`assets/icons/inutil_icon.png`).
- **Selector de tramo estilo Reels/Estados (5–30 s)**:
  - Duración inicial: 15 s (chips rápidos `10s`, `15s`, `20s`, `30s` + ajuste fino del inicio deslizando la ventana en la barra temporal).
  - Botón de **escucha previa** (reproduce/pausa exactamente el tramo seleccionado).
  - Si hay letras sincronizadas, chips rápidos para anclar el inicio al timestamp exacto de una línea de letra.
- Acciones de salida: **Compartir** (`share_plus` con `video/mp4`) y **Guardar** (`AndroidFileExportChannel` con `video/mp4`), con barra de progreso en vivo y botón de **Cancelar**.

## 2. Enfoques Evaluados y Elección

| Enfoque | Resumen | Trade-off | Decisión |
|---|---|---|---|
| **1. Motor nativo Android (Media3 Transformer Audio + EGL/OpenGL ES + MediaCodec H.264)** | Audio recortado y transcodificado con `media3-transformer:1.4.1` (misma versión ya en `build.gradle.kts`); video compuesto offscreen en GPU a 1080×1920 CFR con Canvas/Skia + faststart MP4. | El overlay exportado se dibuja en Kotlin replicando ambos modos en vez de leer widgets Flutter; a cambio logra 1080p60 real en ~4–8 s sin inflar el APK. | **Elegido** |
| **2. Captura `RepaintBoundary.toImage()` cuadro a cuadro + mux nativo** | Flutter dibuja cada frame del overlay y se lee de GPU a CPU. | 30–90 s por clip, alto uso de RAM/calor y obliga a bajar calidad a 720p30. | Descartado |
| **3. Empaquetar FFmpeg en APK** | Binario FFmpeg por ABI. | +35–45 MB por ABI, `ffmpeg_kit_flutter` archivado, codificación CPU lenta. | Descartado |

## 3. Especificación Técnica de Calidad ("Tipo iPhone" para Redes)

- **Resolución:** `1080 × 1920` (9:16 exacto); fallback automático a `720 × 1280` solo si el encoder del dispositivo rechaza 1080p.
- **Framerate:** Constante (**CFR**) `60 fps` en dispositivos modernos (`minSdk 24` con sondeo de capacidades del `MediaCodec`; fallback seguro a `30 fps` si el encoder no soporta 1080p60).
- **Video Codec:** `video/avc` (H.264 High Profile cuando el encoder lo admite, `I-frame` cada 1 s, color `BT.709` SDR limitado, bitrate calibrado dinámicamente ~7–10 Mbps para máxima nitidez sin exceder límites cómodos de WhatsApp HD).
- **Audio Codec:** `audio/mp4a-latm` (AAC-LC, 48 kHz, estéreo, 192 kbps) recortado con `Media3 Transformer` desde la fuente activa (YouTube Opus/WebM, M4A, MP3, FLAC, HLS o archivo local) + fade-in/out suave.
- **Contenedor:** MP4 con átomo `moov` reubicado al inicio (**faststart**) para reproducción instantánea y preservación de calidad en WhatsApp/Instagram/TikTok.
- **Marca de agua:** Logo `assets/icons/inutil_icon.png` + texto `"Inútil Music"` en esquina inferior derecha (o zona segura limpia) con opacidad sutil (~42–50%), sombra difusa suave y bordes redondeados.

## 4. Arquitectura de Módulos

### Android nativo (`android/app/src/main/kotlin/com/inutilmusic/app/moment/`)
1. `MomentExportModels.kt` — contrato de solicitud/progreso y perfiles de calidad (bitrate/fps/resolución).
2. `MomentAudioExtractor.kt` — extrae y recorta `[startMs, endMs]` a `.m4a` AAC vía `androidx.media3:media3-transformer:1.4.1` respetando HTTP headers y archivos locales.
3. `MomentOverlayRenderer.kt` — dibuja overlays 1080×1920 con `Canvas`/Skia, fuentes `Roboto` empaquetadas de `flutter_assets/assets/fonts/`, arte de portada, letras sincronizadas (con soporte palabra por palabra si existe `words`) y marca de agua translúcida de Inútil Music en los modos `lyrics` y `player`.
4. `MomentVideoCompositor.kt` — pipeline EGL 1.4 + OpenGL ES 2.0 + `MediaCodec` H.264 + decodificador OES en bucle para Canvas/Video Preview (o fondo de portada con blur + movimiento Ken Burns + aura ambiental si no hay video) + `MediaMuxer`.
5. `Mp4Faststart.kt` — relocalizador puro en Kotlin que mueve el átomo `moov` antes de `mdat` actualizando `stco`/`co64`.
6. `InutilMomentExporterPlugin.kt` — `FlutterPlugin` en `inutil_music/moment_exporter` (+ `EventChannel` de progreso), cancelación limpia, gestión de caché temporal en `<cacheDir>/inutil-moment-clips/`.

### Flutter (`lib/`)
1. `lib/services/sharing/moment_clip_models.dart` — modelos inmutables y lógica de ventana/clamp (`5s..30s`).
2. `lib/services/sharing/moment_clip_export_service.dart` — canal nativo + `shareClip()` (`share_plus`) + `saveClip()` (`AndroidFileExportChannel`) + limpieza de caché expirado.
3. `lib/features/music/presentation/providers/player_controller.dart` — método `resolveExportableAudioSource()` que expone URI + HTTP headers (o `file://` local) de la pista actual.
4. `lib/features/music/presentation/widgets/moment_share_sheet.dart` — UI completa del editor y progreso de exportación.
5. Integración en `lyrics_page.dart`, `spotify_fullscreen_canvas_player.dart`, `player_panel.dart` y `app_strings.dart`.
