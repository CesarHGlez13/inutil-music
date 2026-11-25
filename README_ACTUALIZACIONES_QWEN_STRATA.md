# Guía Compacta de Desarrollo y Lanzamiento (Qwen Strata / Agentes)

> **App Oficial:** **Inutix Music** (ecosistema **inutix.com** junto con **Inutix TV** / **Familia Inutix**)
> **Package ID Android:** `com.inutilmusic.app` *(namespace interno; NO cambiar para no romper OTAs)*
> **Repo:** `/home/cesar/Escritorio/alo/inutil_music` → `CesarHGlez13/inutil-music` (rama `master`)
> **Versión base actual:** `2.5.32+4290`

---

## Reglas Críticas (No Romper)

1. **Marca visible:** usar siempre **Inutix Music** / **iX MUSIC** / **Familia Inutix** (nunca `Inútil Music` ni `BStream` en UI ni notas de versión).
2. **Aislamiento de proyectos y dispositivos:**
   - **NUNCA** instalar APKs en el Galaxy S7 Edge (`ad09160360308ca38a`) — es el servidor SQLite autoritativo de `api.inutix.com`.
   - Instalar pruebas Android solo en el Xiaomi (`a586e98a`, `arm64-v8a`).
   - Cambios en `/home/cesar/Escritorio/alo/tvtv` deben documentarse en `tvtv/README.md` y `tvtv/README_ACTUALIZACIONES_QWEN_STRATA.md`.
3. **OTAs opcionales por defecto:** `tool/publish_release.sh` mantiene `MIN_SUPPORTED=2.5.26` y `MANDATORY=0`. Solo usar `MANDATORY=1` cuando César pida un cambio crítico obligatorio.
4. **Sincronizar siempre 7 archivos antes de compilar OTA:**
   - `pubspec.yaml` (`version: X.Y.Z+N`)
   - `lib/core/constants/app_constants.dart` (`appVersion = 'X.Y.Z'`)
   - `CHANGELOG.md` (`## X.Y.Z+N — YYYY-MM-DD`, notas 100 % orientadas al usuario)
   - `README.md` (badge/versión)
   - `install.sh` (versión Linux)
   - `packaging/windows/InutilMusic.iss` (`MyAppVersion`)
   - `test/core/constants/app_metadata_test.dart` (`expect(AppConstants.appVersion, 'X.Y.Z')`)

---

## Ahorro de Contexto (Obligatorio para Qwen Strata)

Varios archivos superan 5,000 líneas (`home_page.dart`, `player_panel.dart`, `settings_panel.dart`, `firebase_playback_sync_service.dart`, `lyrics_page.dart`). **NO leas archivos completos**: usa `grep -n` primero y lee solo bloques de 60–150 líneas.

| Área | Archivo principal |
| :--- | :--- |
| Marca y versión | `lib/core/constants/app_constants.dart` |
| Navegación, Home, Mini-player y anclas de guía | `lib/features/music/presentation/pages/home_page.dart` |
| Recorrido interactivo en vivo + Tips contextuales | `lib/features/music/presentation/widgets/inutix_live_guide.dart` |
| Reproductor completo + menú `⋯` | `lib/features/music/presentation/widgets/player_panel.dart` |
| Reproductor Canvas pantalla completa + botón Compartir | `lib/features/music/presentation/widgets/spotify_fullscreen_canvas_player.dart` |
| Estudio «Compartir momento» (MP4 1080p 60 fps) | `lib/features/music/presentation/widgets/moment_share_sheet.dart` |
| Auth, licencias, recuperación de sesión y Panel Admin | `lib/core/firebase/firebase_auth_service.dart`, `inutil_auth_gate.dart`, `inutil_admin_panel.dart` |
| Infra `inutix.com` y failover LAN→api→backup | `lib/core/firebase/firebase_config.dart`, `firebase_firestore_service.dart` |
| Inutix Connect (LAN + nube, aislamiento por cuenta) | `lib/core/firebase/firebase_playback_sync_service.dart`, `inutil_connect_sheet.dart` |
| Persistencia de última canción y posición (min:seg) | `lib/features/music/data/datasources/playback_resume_store.dart`, `player_controller.dart` |
| Listening Rooms (sync host/invitado, cola votada, deep links) | `lib/core/firebase/listening_room_service.dart`, `listening_room_providers.dart`, `listening_room_sheet.dart` |
| Ajustes y Acerca de | `lib/features/music/presentation/widgets/settings_panel.dart` |
| Relay autoritativo S7 Edge | `/home/cesar/Escritorio/alo/inutil_relay/relay.py` |

---

## Comandos Rápidos de Validación y Lanzamiento

```bash
cd /home/cesar/Escritorio/alo/inutil_music

# 1. Análisis rápido filtrado (evita saturar contexto)
flutter analyze --no-fatal-infos lib/features/music/presentation/widgets/inutix_live_guide.dart 2>&1 | grep -E "^\s*(error|warning)" || echo "OK"

# 2. Pruebas clave en formato compacto (NUNCA correr flutter test en paralelo con flutter build apk)
flutter test -r compact test/core/constants/app_metadata_test.dart test/v2_5_30_live_interactive_guide_test.dart test/core/firebase/session_recovery_and_connect_isolation_test.dart

# 3. Compilar APKs de producción con endpoints inutix.com horneados
flutter build apk --release --split-per-abi \
  --dart-define=FB_RELAY_HOST=192.168.100.27 \
  --dart-define=FB_CLOUD_RELAY_HOST=api.inutix.com \
  --dart-define=FB_BACKUP_RELAY_HOST=backup.inutix.com

# 4. Empaquetar Linux (.tar.gz + .deb) y publicar OTA opcional en GitHub + S7 + Firestore
bash tool/package_linux.sh
bash tool/publish_release.sh <VERSION> --github
```
