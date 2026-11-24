# Inutix Music

![Flutter 3.47.9](https://img.shields.io/badge/Flutter-3.47.9-02569B?logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20Linux%20%7C%20macOS-blue)
![Version](https://img.shields.io/badge/version-2.1.0%2B210-brightgreen)
![Release](https://img.shields.io/badge/release-v2.1.0-brightgreen)
![License](https://img.shields.io/badge/license-BSD--2--Clause-green)

Inutix Music is a cross-platform music player and library manager built with Flutter. It lets you search for music, play and download tracks, organize a local library, and manage playlists on Android, iOS, Windows, Linux, and macOS.

Published artifacts and the update channel live in
<https://github.com/CesarHGlez13/inutil-music>.

Current version: **2.5.29+4287**.

> The repository does not store media content. YouTube search, playback, and
> downloads use Inutix Music's self-contained Dart InnerTube pipeline. Supported
> builds neither bundle nor launch an external media resolver. Users are
> responsible for complying with copyright laws and provider terms.

## Propiedad del código, licencias y plan de independencia

Mientras Inutix Music completa su transición gradual hacia un código fuente 100 % reescrito desde cero, este repositorio distingue explícitamente la titularidad de cada bloque conforme a `LICENSE` y `THIRD_PARTY_NOTICES.md`:

### Qué pertenece 100 % a Inutix Music (`Copyright (c) 2026, Inutix Music`)
- **Identidad visual y marca:** nombre «Inutix Music», iconografía **iX**, glifos vectoriales (`lib/core/theme/inutil_icons.dart`), sistema de diseño (`lib/core/theme/inutil_design_system.dart`) e iconos/recursos propios en todas las plataformas (`assets/icons/`, `res/drawable-nodpi/ic_stat_inutil_music.png`, mipmaps adaptativos, `.ico`, `.appiconset`).
- **Infraestructura Firebase, cuentas, nube y OTA (`lib/core/firebase/`, `firebase/`, `lib/services/app_update/`, `tool/`):** autenticación, acceso por vigencia/inactividad, panel administrativo (`inutil_admin_panel.dart`), respaldo y restauración en la nube de playlists/pistas/ajustes (`inutil_cloud_backup_service.dart`), sincronización de reproducción entre dispositivos, campañas/popup de apoyo, Wrapped (`inutil_wrapped_*`), motor de actualizaciones OTA (`InutilUpdateService`, `OtaDownloadManager`, `AndroidPackageInstaller`, `OtaPlaybackResumeStore`) y scripts de publicación (`tool/publish_release.sh`, `tool/package_linux.sh`).
- **Módulos y pantallas nuevas en Dart/nativo:** motor separado de vistas previas de video (`lib/services/video_preview/video_preview_resolver.dart`, `video_preview_reel_sheet.dart`, `video_preview_provider.dart`), diálogo e importador avanzado de Spotify (`inutil_spotify_import_dialog.dart`), tour interactivo (`inutil_onboarding_tour.dart`), canvas engine (`inutil_canvas_engine.dart`, `InutilCanvasEnginePlugin.kt`, `spotify_fullscreen_canvas_player.dart`), enlace canónico (`inutil_track_link.dart`), hoja Connect/SleepTimer/Account (`inutil_connect_sheet.dart`, `inutil_sleep_timer_sheet.dart`, `inutil_account_dialog.dart`) y enrutamiento Mesa EGL en Linux NVIDIA (`linux/runner/main.cc`) + icono `_NET_WM_ICON` (`linux/runner/my_application.cc`).

### Qué proviene de la base de Bryam Contreras (`Copyright (c) 2026, Bryam Contreras` — BSD 2-Clause)
- **Núcleo y módulos base en `lib/`:** `375` archivos `.dart` compartidos con el repositorio original (`262` sin cambios + `113` con adaptaciones propias; aprox. `87.7 %` de líneas heredadas en `lib/`), incluyendo la mayor parte de `features/music/presentation/`, `services/youtube_music/`, `services/player/`, `services/storage/`, `services/downloader/`, `services/lyrics/`, `services/live/`, `services/casting/`, `services/recommendations/`, `services/jiosaavn/` y `core/widgets/`.
- **Capas nativas adaptadas/renombradas:** wrappers base en `android/app/src/main/kotlin/com/inutilmusic/app/` (migrados desde el paquete original), `ios/Runner/`, `ios/NowPlayingWidget/`, `macos/Runner/`, `windows/runner/` y base del runner GTK en `linux/runner/`.

### Componentes de terceros externos
- Incluyen `just_audio` 0.10.6 (fork local bajo **MIT** + ExoPlayer/Media3 **Apache-2.0**, ver `third_party/just_audio/LICENSE`), `Kyant AndroidLiquidGlass` (**Apache-2.0**), `piratetok_live` (**0BSD**), `EJS` (**Unlicense** / `meriyah` **ISC** / `astring` **MIT**), `csv` y `xml` (**MIT**), SDKs de Google Cast y dependencias de Flutter (`THIRD_PARTY_NOTICES.md` y visor en *Ajustes → Acerca de → Licencias de código abierto*).

### Objetivo y plan paso a paso
El objetivo a mediano plazo es **reemplazar de forma limpia (*clean-room*) cada módulo heredado por código 100 % propio**, conservando intacto el aviso `Copyright (c) 2026, Bryam Contreras` en `LICENSE` y `THIRD_PARTY_NOTICES.md` hasta completar la última fase (`0` líneas heredadas). Consulta la hoja de ruta técnica y legal completa en [`docs/INDEPENDENCE_PLAN.md`](docs/INDEPENDENCE_PLAN.md).

<img width="1221" height="840" alt="{3AC80665-A6EC-436D-9C87-A1413432F0E3}" src="https://github.com/user-attachments/assets/8c918bae-6f84-46fa-8923-24ea68b6f8a4" />

## What's new in 1.3.1

- The player now supports higher quality audio when available.
- Improved and optimized the layouts of the player styles.
- Added the new Spotify Style player.
- Added filtering options in the Local music tab.
- Added support for word-synchronized lyrics when word timing is available.
- Improved the design of the Settings tab.
- Customize playlist artwork with an image from your gallery.

## Main features

### Search, downloads, and library

- Optional YouTube Music account sign-in and bidirectional playlist sync. New
  local playlists are created remotely as private playlists, imported remote
  playlists may contain streaming-only entries, and Inutix Music Favorites maps to
  YouTube Music's **Liked Music** collection. The system playlist “Episodes for
  later” is intentionally excluded.
- Synced playlist playback is download-first: Inutix Music uses a valid local copy
  when available and falls back to streaming the same catalog entry when the
  file is missing or cannot be opened.
- InnerTube search tabs for Songs, Videos, and Albums, with up to 20 results,
  artwork, metadata, and album queues loaded only when selected.
- InnerTube discovery keeps Songs, Videos, Albums, artists, and releases on the
  same Dart transport used by playback.
- Empty Search offers responsive mood and genre cards. Live YouTube Music
  browse targets are preserved exactly, playlist-only shelves are expanded
  into bounded song queues, and curated/search fallbacks keep the view useful
  when the device is offline or the remote layout changes.
- Search text remains available between searches and has an inline clear action.
- Remote song rows in Search and album, playlist, and mix details provide a
  dedicated Play/Pause control and a More menu for Download and Add to
  playlist; tapping the row still opens the full player.
- Remote playback and audio downloads with real-time progress.
- Direct YouTube playback and downloads use a maintained, deterministic Dart
  InnerTube client ladder with page-specific dynamic bootstrap. Solver-dependent
  retries use pinned EJS modules in a headless JavaScript runtime and generate
  Web BotGuard PO tokens only for profiles that require them; degraded fallback
  tokens fail closed and independent EJS/WebPO capability circuit breakers
  advance immediately to tokenless clients. If an active stream loses
  connectivity, Inutix Music
  retries the resolver chain with bounded backoff; navigation cancels obsolete
  attempts. YouTube candidates are deep-probed at or beyond 3 MiB before
  publication, and downloads resume through validated range requests and safe
  `.part` files. Native M4A/AAC, WebM/Opus, and other available audio
  containers remain unconverted; when YouTube exposes only a direct muxed
  fallback, it is preserved as `.mp4` instead of being mislabeled or
  transcoded.
- Optional JioSaavn audio upgrades follow the selected Wi-Fi/mobile profile.
  YouTube Music remains enabled and starts playback first. A bounded lookup
  checks the recording's title, version, artists and duration before preparing
  a verified higher-bitrate rendition on the existing muted standby deck.
  Promotion retains catalog metadata, queue and position, with a short linear
  transition; missing matches or failed preparation leave YouTube playing.
  Settings expose both sources under Integrations and quality under Storage >
  Data saving. Desktop has one quality choice for all connections. On mobile,
  Wi-Fi defaults to High/JioSaavn and cellular to Standard/YouTube Music.
  Disabling JioSaavn applies Standard without erasing
  saved preferences. A headphones quality capsule shares each player's elapsed/
  duration row and reflects the actual stream, not the requested profile.
- High-quality artwork uses one proportional crop policy from search through
  playback and downloaded-library storage.
- SQLite-backed local library.
- Reuse of downloaded tracks to avoid duplicate downloads.
- Filtering, renaming, and deletion of saved tracks.
- The Local music header's More menu provides the same filtering options as
  the library, and local song cards include a dedicated Play/Pause control.
- Playlist creation, renaming, and deletion.
- Tap a saved playlist's cover to keep its random song-artwork mosaic or choose
  a custom image. Gallery photos use the same crop editor as lyric sharing,
  fixed to a square; custom covers follow media-folder moves and ZIP backups.
- Playlist and downloaded-song headers show both song count and total duration.
- Dedicated **Favorites** playlist with accent-colored hearts on favorited
  tracks.
- ZIP backup and restore for the database, audio files, and thumbnails.
- CSV imports recognize Inutix Music, MetroList, Harmony/RiMusic, Soundiiz,
  Exportify, and common title/artist/album/ISRC layouts. They show a preview,
  reuse existing local tracks, and process up to three missing songs
  concurrently only after confirmation while retaining source playlist order.
  Exports offer Inutix Music, MetroList, Harmony/RiMusic, and Soundiiz profiles
  and contain metadata, not audio.

### Player

- Play, pause, previous, next, repeat, and shuffle controls.
- Shared Lyrics, Queue, Audio output, and Volume icons keep controls consistent
  across the app. Full-player utility rows adapt their spacing to each style.
  A heart beside the track metadata toggles Favorites, with More options
  beside it.
- Share in the player's More menu sends one canonical HTTPS URL that chat
  applications can recognize: YouTube Music when the track came from the
  InnerTube catalog, otherwise the regular YouTube watch URL. Local-only files
  without a YouTube identity are intentionally not shared.
- Android can also offer Inutix Music when opening public YouTube/YouTube Music
  links. Video links open the player directly; playlist and album links open a
  catalog view with Play and Add to playlist actions. Unsupported or unsafe
  URLs are ignored.
- Lyrics offer three persistent animation styles (Smooth by default),
  Normal/Centered alignment, optional per-script romanization, and a live
  preview in Appearance settings.
- Appearance opens a dedicated gallery with responsive previews of Inutix Music
  Music, Apple Music Style, Classic Vinyl, and Spotify Style. Selecting a style
  applies it immediately. Their controls and artwork adapt to portrait,
  compact landscape, large phones, and desktop windows.
- Crossfade uses coordinated playback decks and supports every whole-second
  duration from 1 through 15 seconds on Android and desktop.
- Android can conservatively shorten confirmed prolonged silence in streaming
  or downloaded songs without disabling crossfade or treating quiet music as
  empty audio.
- Playback queue synchronized with playlists and the library.
- On mobile, swipe the mini player left for Next or right for Previous; short
  drags return to place without changing the song.
- The desktop mini player opens the queue from any tab. Mobile provides a
  dedicated queue view.
- Change tracks directly from the queue and reorder them with a long press.
- Android keeps a rolling native queue for remote playback, with up to three
  upcoming tracks prepared sequentially so locked-screen transitions do not
  depend on reopening the app. The bounded disk window prioritizes the current
  track, those three upcoming tracks, and the previous track; interrupted-
  session leftovers expire after 30 minutes.
- On Android, Quick picks that omit catalog duration adopt ExoPlayer's detected
  duration after loading, keeping the timeline and seeking available.
- Desktop also prepares up to three upcoming remote tracks as complete local
  files. Its 12-hour LRU cache keeps at most 24 files, 256 MiB total, and
  128 MiB per track; changing queues or stopping playback releases protection
  without discarding reusable audio. Minimizing or locking the PC keeps the
  player running, while closing the application exits playback.
- The active track is highlighted with a segmented 13-bar equalizer.
- Theme-aware dynamic background derived from the track artwork.
- Animated progress waves use the current artwork's color, with a smooth color
  transition and an accent-color fallback when artwork is unavailable.
- Volume is available directly in the player controls.
- On Windows, Linux, and macOS, choose Inutix Music's audio output device from the
  player's More menu, with independent player volume and crossfade support.
- On desktop, Space toggles Play/Pause from the mini or full player unless an
  editable text field such as Search currently has focus.
- Synchronized lyrics from Better Lyrics, LyricsPlus, and LRCLIB, with automatic
  word/syllable highlighting when valid timing is supplied and line-by-line or
  plain-lyrics fallback. Supports automatic scrolling, tap-to-seek, and a manual
  timing offset from `-10` to `+10` seconds in `0.50`-second steps. Timed
  instrumental passages respect sustained words before showing a filling wave.
- Sleep timer with quick durations and a custom duration.
- Native system media integration: Android media notifications, iOS and macOS
  Now Playing, Windows SMTC, and Linux MPRIS.
- Source opens use bounded deadlines and generation/epoch isolation. A broken
  decoder or network source cannot hold a newer selection, Stop, or shutdown
  indefinitely, and late events from the retired source are ignored.
- Windows registers a stable application identity so SMTC shows the Inutix Music
  Music name and icon in system media controls.
- Failed-track handling: a track that cannot be downloaded or played does not leave the queue stuck on the previous track.

### Interface

- Responsive mobile and desktop layouts with bounded artwork decoding,
  lazy library lists, 48 dp touch targets, and large-text adaptation.
- System, Light, and Dark themes with eighteen persistent accent palettes.
  Lyrics and the mobile full player use a consistent dark playback surface;
  the desktop full player, browsing, queues, menus, and settings follow the
  selected application theme.
- Navigation remembers only the two most recent views.
- Returning from the player restores the previously opened playlist or section.
- Home displays up to 10 recently played items and 10 playlists. Recent items
  restore their last valid source playlist and fall back safely when that
  playlist no longer exists.
- Without requiring an account, Home learns only from qualified local playback
  events and combines YouTube Music related candidates with Inutix Music's own
  ranking. Personalized shelves include **Because you listened**, **Your
  mixes**, **New for you**, and **Discovery for you**; the previous feed is
  shown instantly while a fresh one is prepared in the background.
- Recommendation learning can be paused or its local history and caches can be
  cleared from Privacy settings without removing downloads, favorites, or
  playlists.
- Subtle gradients, translucent cards, and shared visual controls.
- Spanish, English, Portuguese, French, Korean, Simplified Chinese, and Japanese
  selectable from Settings, including localized release highlights.
- An Application information section in Settings opens an organized About the
  app detail with the current version, optional Ko-fi development support, and
  the official GitHub repository; Inutix Music remains free.
- Windows window minimum size of `960 × 600`; the player progressively adapts artwork, text, spacing, and controls to the available height.
- Icons generated from one source asset for Android, iOS, Windows, macOS, and
  Flutter resources.

## TikTok LIVE on Android, iOS, Windows, Linux, and macOS

Every supported Inutix Music platform connects to TikTok LIVE through a client
implemented directly in Dart and turns chat commands into a temporary music
queue. The integration does not launch an external bridge.

Available features:

- Connect using `@username` or `https://www.tiktok.com/@username/live`.
- Detect the user who requested each track.
- Identify followers, subscribers, and moderators from each chat message.
- Configure every command independently for **Everyone**, **Followers**,
  **Subscribers**, and **Moderators**.
- LIVE queue states for searching, downloading, ready, and failed requests.
- A bounded 50-request queue that rejects additional commands explicitly
  instead of allowing an unbounded search/download backlog.
- Up to three requests are resolved concurrently, while completed tracks are
  committed to playback in the same order in which their commands arrived.
- A 30-second search deadline lets later requests continue past a stalled
  lookup; an active library download is allowed to finish normally.
- Command-first chat filtering and early WebSocket acknowledgements avoid
  building full viewer profiles for ordinary comments in busy rooms.
- Reuse tracks that already exist in the library.
- Dynamic synchronization: new requests are added without replacing the current playback.
- Automatically skip requests that fail during download.
- On Windows, expose the current LIVE song and the next four requests as a
  transparent browser overlay at
  `http://overlay.inutilmusic.test/overlay`. Playback, queue, artwork,
  progress, accent, and language changes are pushed immediately over the
  integrated `ws://overlay.inutilmusic.test/ws` connection.

Recognized commands:

```text
!play song name
!skip
!next
!revoke
!stop
revoke!
```

`!play` searches for the first result, prepares it, and adds it to the queue.
`!skip`/`!next` advance playback. `!revoke`/`revoke!` remove the last request
from the LIVE queue, while `!stop` pauses the current LIVE song.

The local LIVE overlay is available only in the Windows build. Connect to LIVE
and enable **Local LIVE overlay** immediately below the connection control.
On first use, Windows asks for administrator confirmation once so Inutix Music can
add its marked `hosts` entry:

```text
127.0.0.1 overlay.inutilmusic.test
```

Afterward, activating the overlay does not need elevation. The name uses the
reserved `.test` namespace, contains neither `localhost` nor a raw IP, and has
no explicit port, while Windows still resolves it directly to this PC. Inutix Music
listens exclusively on `127.0.0.1`; it does not publish the server to the LAN
or Internet. No HTTPS
certificate is created or installed for the overlay.

Inutix Music reports the overlay as active only after the hostname resolves safely
and a direct request to its local `/health` endpoint succeeds. These checks use
bounded retries, never use an HTTP proxy, and release port `80` completely if
startup cannot be verified.

Windows compatibility and environmental limits for this local overlay are
documented in [Windows LIVE overlay compatibility](docs/windows_live_overlay_compatibility.md).
In short, Windows 11 x64 is supported, Windows 10 22H2 x64 is retained as
legacy compatibility, and Windows 11 ARM64 is experimental through x64
emulation; this is not a guarantee for every Windows device or policy.

In TikTok LIVE Studio, add a web/browser source with these settings:

- URL: `http://overlay.inutilmusic.test/overlay`
- Canvas: `1280 × 760`
- Background: transparent; no chroma-key filter is necessary

On desktop, open **Settings → Appearance → Live widget** to preview and select
**Classic** or **Wave**. Classic keeps the compact queue cards. Wave displays
larger artwork, a blurred metadata panel, an animated wave between the playback
times, and a full-width progress bar. Both styles use the app accent and keep
the scene background transparent. The choice is saved and updates an active
Windows browser source immediately; no reconnect is required. The wave pauses
with playback, when the browser source is hidden, and for reduced motion.

Keep Inutix Music running while the source is in use. The page contains its own
HTML, CSS, and JavaScript and receives queue updates from Inutix Music over WS; it
does not contact an external overlay service. Port `80` must be free because an
HTTP URL without an explicit port necessarily uses it; Inutix Music reports an error
instead of stopping or reconfiguring another application that already owns the
port. If Windows access is declined, the rest of Inutix Music remains unaffected and
the overlay can be activated again later.

To preview and style the real HTTP/WS overlay without installing or
connecting the app, run `dart run tool/live_overlay_preview.dart`, open the
printed URL, and press `Ctrl+C` when finished. The same one-time Windows
confirmation is required if the local domain has not been configured yet.
For an isolated preview without configuring the domain, add `--loopback`;
`--style=wave` selects the new design. Run
`node tool/live_overlay_browser_smoke.mjs --capture` with Chrome or Edge
installed to check both layouts and save screenshots under `build/`.

On Android, the connection can continue while the app is normally in the
background as long as its Flutter process remains alive. Force-stopping the app
or Android reclaiming that process also ends the LIVE connection; it is not an
independent background service.

This integration uses an unofficial, reverse-engineered protocol. If TikTok
changes it, the Dart client may need to be updated. Inutix Music is not
affiliated with or endorsed by TikTok or ByteDance. Inutix Music can keep its local
processing responsive, but it can only act on chat messages that TikTok
actually delivers to the WebSocket client.

## Platforms and engines

| Platform | Player | Downloads | Notes |
| --- | --- | --- | --- |
| Android | `just_audio` + `audio_service` | Dart InnerTube | `minSdk 24`; optional headless WebView for EJS and Web BotGuard PO tokens; TikTok LIVE; open local audio from Android; release APKs support `armeabi-v7a`, `arm64-v8a`, and `x86_64` |
| iOS | `just_audio` + `audio_service` | Dart InnerTube | iOS 13 or newer; embedded account login and optional headless WebView challenges; background audio and Now Playing; TikTok LIVE; native access to locally available, non-DRM songs in the Media Library; CI publishes an unsigned IPA for use with a compatible external signing tool |
| Windows | `media_kit` | Dart InnerTube | Optional headless WebView for EJS and Web BotGuard PO tokens; SMTC controls, TikTok LIVE, queue side panel, and the integrated loopback-only HTTP/WS LIVE overlay |
| Linux | `media_kit` | Dart InnerTube | Three tokenless/JS-less InnerTube identities (`visionOS`, `androidSdkless`, `visionOS01`); MPRIS controls; TikTok LIVE; Ubuntu 22.04-based x64 installers; requires GTK 3, libmpv, SQLite, and libsecret |
| macOS | `media_kit` | Dart InnerTube | Optional headless WebView for EJS and Web BotGuard PO tokens; Now Playing controls, TikTok LIVE, separate PKG installers for Apple Silicon and Intel; minimum window `960 × 600` |

YouTube playback and downloads prefer the best available native M4A/AAC stream,
otherwise the best original compatible audio stream. When the current network
profile requests High and JioSaavn is enabled, the optional resolver verifies a
matching recording and a real higher-quality CDN rendition. Playback starts
YouTube immediately and looks for the improvement in the background; downloads
select the verified rendition before transferring the file and fall back to
YouTube if the optional CDN fails. Search results and all library metadata keep
their YouTube Music identity. Renditions and partial downloads from different
providers have separate cache/file identities. Desktop uses its single saved
quality without querying the connection type. On mobile, unknown connectivity
uses Standard and Ethernet uses the Wi-Fi profile. Connection checks are shared
and event-driven, without internet polling.

The JioSaavn adapter uses bounded public API requests and URL decoding in Dart,
requires the catalog's actual 320 kbps flag and a small playable-CDN range probe,
and uses the reference client's catalog compatibility headers only on JioSaavn
API requests. These headers are not forwarded to audio CDNs, YouTube or player
requests. Technical labels reuse the local MP4/AAC header parser to obtain the
selected stream's declared bitrate, sample rate and channels. The optional
header lookup reuses the verification prefix, skips audio payloads and has
bounded bytes, requests and elapsed time; unavailable details remain unknown
without preventing a verified source upgrade. Catalog availability depends on the track
and region; an unavailable recording remains on YouTube. Its source-upgrade
behavior was researched against [BitChord](https://github.com/kushagrasinghx/BitChord)
and implemented independently for Inutix Music's existing playback infrastructure.

Inutix Music preserves the original audio samples and does not extract, remux, or
transcode them. Compatible downloaded files receive
embedded title, artist and album before entering the library, reusing the
resolved catalog data. Container detection uses the file contents, with these
tagging capabilities:

| Audio container | Embedded artwork | Tag format |
| --- | --- | --- |
| M4A / audio-only MP4 (AAC or ALAC) | Yes | iTunes `ilst` |
| MP3 | Yes | ID3v2.3 / ID3v2.4 |
| FLAC | Yes | Vorbis comments and PICTURE |
| Ogg Opus / Ogg Vorbis | Yes | Comments and METADATA_BLOCK_PICTURE |
| WAV (RIFF PCM/float) | Yes | ID3 chunk |
| APE (Monkey's Audio) | Yes | APEv2 |
| Audio-only WebM / Matroska (Opus/Vorbis) | External cached image | Text Tags |

Embedded covers reuse the saved JPEG/PNG thumbnail. WebM's supported subset
does not include cover attachments, so its image remains in the existing cache;
tagging never changes the container or renames the file. Tagging runs outside
the UI thread, copies media in bounded blocks and validates a temporary file
before replacing the original. The format writers share atomic publication and
copying, while FLAC and Ogg share comment/picture handling. Existing unrelated
tags are preserved; repeating the same update skips rewriting the audio. Unsafe,
malformed or unsupported layouts retain the original download, including
encrypted streams, multiplexed/chained Ogg, RF64 and unsupported legacy ID3 flags.
Library metadata remains in SQLite and artwork is also kept as a separate
thumbnail for fast browsing. The downloaded-songs menu can update existing
owned downloads from their saved metadata without downloading them again;
files currently open in the player are skipped.

Playback of the app-owned library uses its SQLite-backed track records and
shared in-memory state for titles, artists, albums and cached artwork. Embedded
tags are kept for portability; the player does not reread them to rebuild that
information when a song starts. The Local tab has a separate device catalog:
desktop scans read text tags in a background isolate, while Android and iOS
reuse their native media indexes. Filtering, revisiting the tab and playback
reuse each catalog's session snapshot; refreshing updates the device catalog.
Mobile device artwork is requested separately on demand rather than extracted
for every song during a library scan. Desktop text scans skip embedded images.

Inutix Music does not invoke or bundle standalone `ffmpeg` or `ffprobe`
executables. Desktop playback still relies on the codec libraries included by
`media_kit`/libmpv; those libraries decode M4A, Opus, and other formats during
playback, but they are not a transcoding or download post-processing step.

Lyrics are requested from the selected Better Lyrics, LyricsPlus, and
[LRCLIB](https://lrclib.net) providers when the lyrics view is opened. Inutix Music
sends the current title, artist, duration, and album when available, identifies
itself with the required client header, and keeps bounded 15-minute in-memory
caches of at most 24 songs per provider to avoid duplicate requests. Word timing
from TTML, LyricsPlus words/syllables, and Enhanced LRC is retained in that cache.
Lyrics are not embedded in downloaded audio files, and this cache disappears
when the app process closes.

## Architecture

The interface is isolated from SQLite, the media engines, and provider
protocol details. Communication flows through entities, use cases,
repositories, providers, and interchangeable services. The remote catalog,
playback, and download stack is implemented directly in Dart without a
vendored extractor library or companion resolver runtime.

```text
lib/
  core/
    constants/
    errors/
    platform/
    utils/
  features/music/
    domain/
      entities/
      repositories/
      usecases/
    data/
      datasources/
      models/
      repositories/
    presentation/
      pages/
      providers/
      widgets/
  platform_channels/
  services/
    downloader/
    youtube_music/
      playback/
    live/
    lyrics/
    media_session/
    player/
    storage/
third_party/
  piratetok_live/
```

The main contracts are `DownloaderService`, `AudioStreamResolver`,
`PlayerService`, `LyricsService`, and `LibraryRepository`. The
InnerTube playback implementation is isolated under
`lib/services/youtube_music/playback/`; downloader and resolver adapters expose
it through the app contracts without leaking protocol types. Android uses
platform channels for unrelated native tasks; YouTube resolution and transfer
remain inside the Dart service layer on every platform.

## Development requirements

- Stable Flutter 3.47.9 or newer, compatible with Dart `^3.12.0`.
- Android Studio and Android SDK for Android development.
- Visual Studio/Build Tools with **Desktop development with C++** for Windows.
- The pinned NuGet CLI on `PATH` for Windows plugin dependencies (the build
  bootstrap below installs it when needed).
- A stable Rust toolchain with the MSVC x64 target for Windows SMTC builds.
- Clang, CMake, Ninja, GTK 3, libmpv, SQLite, and libsecret for Linux.
- A Mac with Xcode and CocoaPods to build and test iOS or macOS. Creating the
  unsigned iOS application and IPA needs no Apple certificate; direct device,
  TestFlight, and App Store installation still require an accepted signature
  and provisioning method.

CI uses Flutter 3.47.9 for every target. Each build packages the matching
Flutter engine with the application. Android keeps Flutter's automatic
renderer selection; Liquid Glass rendering paths depend on the platform and
available shader support.

Check the environment with:

```powershell
flutter doctor -v
flutter pub get
```

## Run the project

```powershell
flutter run -d windows
flutter run -d android
flutter run -d <ios-device-id>
flutter run -d linux
flutter run -d macos
```

List available devices with:

```powershell
flutter devices
```

## Windows build dependencies

The Windows WebView login needs the NuGet CLI at build time. The project now
bootstraps the pinned, checksum-verified CLI automatically during CMake
configuration, so the normal command is enough:

```powershell
flutter clean
flutter pub get --enforce-lockfile
flutter build windows --release
```

If an older generated build still reports `NUGET-NOTFOUND`, delete
`build/windows` once and rerun `flutter run -d windows`; CMake will install the
same pinned tool automatically. The bootstrap also works around the hidden
`AppData` path bug in `smtc_windows` 1.1.0, which otherwise appears as a
misleading `Get-Item C:\\Users\\...\\AppData` error.

The script downloads NuGet `6.12.2` from the official distribution endpoint,
verifies its SHA-256, and stores it under the user/runner tool directory. A
WebView2 Runtime is required to run the login screen on the Windows machine;
it is not required merely to compile the application.

Windows Release builds need no YouTube resolver executable. Playback,
downloads, EJS challenge handling, and optional Web PO-token generation are
provided by the Dart application and its headless WebView runtime.

## iOS support

The iOS runner targets iOS 13 or newer. It registers the `inutilmusic` custom
URL scheme, keeps account credentials in the system Keychain, and enables the
audio background mode for lock-screen and Now Playing controls. Remote search,
playback, downloads, embedded YouTube Music account login, TikTok LIVE, backup
export, and CSV export are adapted to iOS. The system document picker handles
exports outside Inutix Music's sandbox.

The Now Playing home-screen widget is available on iOS 14 or newer (small and
medium sizes). Its artwork and metadata are copied into the shared App Group
`group.com.inutilmusic.app`; the widget never starts an audio engine or
downloads music. Its controls open Inutix Music to execute playback actions. For
device signing, register that App Group for **both** the Runner and
`com.inutilmusic.app.NowPlayingWidget` extension and sign both targets
with profiles that include the entitlement. An external signing tool that
strips the group entitlement or does not sign the extension cannot provide a
working widget. The Android home-screen widget uses the active media session
for its transport controls.

With the user's Media Library permission, the Local view reads songs through
`MPMediaLibrary`. Only media that is downloaded to the device, exposes a
playable asset URL, and is not DRM-protected is listed. Cloud-only Apple Music
items remain unavailable until iOS downloads them locally. Inutix Music's downloaded
tracks remain in its own library as on the other platforms.

The app cannot claim public `youtube.com` links as Universal Links because
those domains do not publish an association for Inutix Music; app-owned
`inutilmusic://` links are the contract owned by Inutix Music.

The repository's CI compiles both an unsigned simulator application and an
unsigned Release application for physical devices. It packages the latter as
`Inutix-Music-<version>-iOS-unsigned.ipa` and uploads it to the corresponding
GitHub Actions run; it does not sign the package or publish it to a store.

The unsigned IPA can be used as input for an external signing or sideloading
tool such as GBox. It is not directly installable in its unsigned state: the
chosen tool must sign or re-sign it using credentials and provisioning that the
target device accepts. GBox and similar services are independent of Inutix Music,
and their availability and compatibility are not guaranteed by this project.

Media Library behavior must be tested on a physical device because it is not
available in the simulator. Xcode device deployment, TestFlight, and App Store
distribution require the corresponding Apple signing and provisioning setup.

## macOS permissions

The application is distributed outside the Mac App Store. App Sandbox is
disabled so Inutix Music can access the selected download folder and make network
connections. Hardened Runtime remains enabled for Developer ID signing and
notarization. Release bundles contain no external YouTube resolver or
JavaScript runtime. TikTok LIVE uses the same in-process Dart transport on
macOS as on Android, Windows, and Linux.

The native macOS window uses the same `960 × 600` minimum as Windows.

## Linux runtime dependencies

The release tarball (`inutil_music_linux_x64.tar.gz`) is **self-contained**: it
bundles `libmpv.so.2` inside `lib/` and ships a ready-to-run `install.sh` at its
root. No system package manager steps are required after download.

A `.deb` package (`InutilMusic-<version>-linux-amd64.deb`) is also published for
users who prefer a system-level installation managed by `apt`/`dpkg`. Its
`Depends` field lists `libgtk-3-0 | libgtk-3-0t64, libmpv2 | libmpv1,
libsqlite3-0, libsecret-1-0` and the package manager installs any missing ones
automatically.

## TikTok LIVE client

TikTok LIVE networking, reconnection, Protobuf decoding, command parsing, and
WebSocket keepalive handling run inside the Dart application. Builds do not
bundle or start a companion runtime for this integration.

The transport uses an audited in-tree fork of the 0BSD-licensed
`piratetok_live` 0.1.5 project. See
[Third-party notices](THIRD_PARTY_NOTICES.md) for attribution.

## Android

YouTube stream resolution and downloads stay in the Dart service layer:

```text
lib/services/youtube_music/playback/
lib/services/downloader/innertube_audio_resolver.dart
lib/services/downloader/innertube_download_service.dart
lib/services/downloader/http_audio_transfer.dart
assets/youtube/po_token.html
```

The playback service routes requests through a maintained InnerTube client
ladder, bootstraps matching page/client context, validates stream ranges, and
falls back between client profiles when a request is rejected. Pinned EJS
modules solve player challenges through the headless WebView runtime, while
Web BotGuard PO tokens are generated only for profiles that require them and
never substitute an unbound fallback token. Downloads reuse the same resolved
streams and a resumable `dart:io` transfer. Android carries no external
resolver executable or embedded resolver runtime.

The remaining app-specific native Android integration is limited to platform
features that Flutter cannot provide directly:

```text
android/app/src/main/kotlin/com/inutilmusic/app/MainActivity.kt
android/app/src/main/kotlin/com/inutilmusic/app/ExternalAudioIntentHandler.kt
android/app/src/main/kotlin/com/inutilmusic/app/LauncherActivity.kt
```

Those classes handle audio-service activity integration, file export, supported
links, screen flags, notification and media permissions, local/external audio
intents, artwork loading, and launcher transitions. There is no native
YouTube-resolver MethodChannel.

Release builds support the 32-bit `armeabi-v7a` (ARMv7), 64-bit `arm64-v8a`
(ARMv8), and emulator/device `x86_64` ABIs. All require Android 7.0 or newer
through the shared `minSdk 24` baseline.

### Release signing

Copy `android/key.properties.example` to `android/key.properties` and configure a key outside the repository:

```properties
storeFile=../release/inutil-upload-keystore.jks
storePassword=...
keyAlias=inutil
keyPassword=...
```

These environment variables are also supported:

```powershell
$env:INUTIL_ANDROID_STORE_FILE="D:\keys\inutil-upload-keystore.jks"
$env:INUTIL_ANDROID_STORE_PASSWORD="..."
$env:INUTIL_ANDROID_KEY_ALIAS="inutil"
$env:INUTIL_ANDROID_KEY_PASSWORD="..."
```

`android/key.properties`, `*.jks`, and `*.keystore` are excluded from Git.

GitHub Actions uses the same signing key through encrypted repository secrets:

```text
INUTIL_ANDROID_KEYSTORE_BASE64
INUTIL_ANDROID_STORE_PASSWORD
INUTIL_ANDROID_KEY_ALIAS
INUTIL_ANDROID_KEY_PASSWORD
```

El workflow pasa esos secretos a las variables `INUTIL_ANDROID_*` que lee Gradle.

The workflow verifies all three APK signatures before uploading the artifacts.

## Database, favorites, and backups

- Android, iOS, and macOS use `sqflite`; Windows and Linux use
  `sqflite_common_ffi`.
- Incremental migrations preserve existing libraries.
- Favorites are implemented as a reserved local playlist (`inutil:favorites`),
  so no separate table is required. After account consent, it is bound to
  YouTube Music's special **Liked Music** collection (LM/VLLM): likes and
  unlikes use the same conservative playlist sync engine, without importing a
  duplicate playlist. “Episodes for later” is ignored during account bootstrap.
- ZIP backups contain the database, `audio/`, `thumbnails/`, and a manifest.
- The Storage page separates local ZIP backup transfer from portable CSV
  transfer. Inutix Music CSV preserves playlist membership and order; importing can
  resolve up to three missing tracks concurrently, and Inutix Music,
  MetroList, Harmony/RiMusic, or Soundiiz can be selected as export profiles.
- Restore validates the manifest, archive paths and limits, SQLite integrity,
  schema, and version before touching local data. Database and media changes
  are staged on their destination filesystems and rolled back if activation
  fails.

## Generate icons

The source asset is `assets/icons/source/ico.png`. Regenerate all variants with:

```powershell
.\scripts\generate_app_icons.ps1
```

The script generates Android mipmaps, opaque iOS AppIcon assets, the Windows
`.ico`, the macOS AppIcon, and Flutter resource variants.

## Build

```powershell
flutter build windows --release
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64
flutter build linux --release
```

On a Mac:

```bash
flutter build macos --release
flutter build ios --simulator --no-codesign
flutter build ios --release --no-codesign
```

The first iOS command produces a simulator application; the second produces the
unsigned device `Runner.app` that CI places inside the standard IPA `Payload/`
layout. After configuring an Apple development team and App Store provisioning,
a maintainer can instead create a signed archive locally with
`flutter build ipa --release`.

Typical artifacts:

```text
build/windows/x64/runner/Release/inutil_music.exe
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
build/app/outputs/flutter-apk/app-x86_64-release.apk
build/linux/x64/release/bundle/inutil_music
build/macos/Build/Products/Release/inutil_music.app
build/ios/iphonesimulator/Runner.app
build/ios/iphoneos/Runner.app
dist/Inutix-Music-<version>-iOS-unsigned.ipa
```

## Release packages with GitHub Actions

The `Release installers` workflow generates signed Android APKs and independent
Release installers for Windows, Linux, and both macOS architectures. Its iOS
job analyzes the project, runs the focused platform tests, compiles unsigned
simulator and device applications, packages the device application as an
unsigned IPA, verifies its structure, and uploads it as a GitHub Actions
artifact. The workflow can be run manually from the **Actions** tab and also
runs for pull requests, pushes to `main`, and `v*` tags.

Desktop jobs build and verify installers without downloading or bundling an
external YouTube resolver. The TikTok LIVE client is also part of the Dart
application and needs no additional runtime. Artifacts are retained for 30
days:

```text
Inutix-Music-<version>-Android-armeabi-v7a.apk
Inutix-Music-<version>-Android-arm64-v8a.apk
Inutix-Music-<version>-Android-x86_64.apk
Inutix-Music-<version>-Windows-x64-Setup.exe
Inutix-Music-<version>-linux-amd64.deb
Inutix-Music-<version>-linux-x86_64.rpm
Inutix-Music-<version>-macOS-arm64.pkg
Inutix-Music-<version>-macOS-x64.pkg
Inutix-Music-<version>-iOS-unsigned.ipa
```

### Which file should I install?

- **Most Android phones and tablets:** install `app-arm64-v8a-release.apk`.
- **Older 32-bit ARM Android devices:** install `app-armeabi-v7a-release.apk`.
- **Android x86_64 devices and emulators:** install `app-x86_64-release.apk`.
- **iPhone and iPad:** download
  `Inutix-Music-<version>-iOS-unsigned.ipa` from the artifacts of a successful
  **Release installers** run in GitHub Actions, then supply it to GBox or
  another compatible signing/sideloading tool. The IPA is deliberately
  unsigned and cannot be installed directly without being signed or re-signed
  by that tool. For Apple's supported development path, run it from Xcode or
  Flutter on a Mac with a development team configured.
- **Windows 64-bit:** open `Setup.exe`. The per-user installer does not require
  administrator access, shows a language selector, creates a Start Menu
  shortcut, and lets you choose whether to create a desktop shortcut. The
  uninstaller entry is displayed as `Inutix Music` without the version number.
- **Ubuntu / Debian / Linux Mint and all `apt`-based distros — easiest way, one command:**

  ```bash
  # Requires curl or wget (curl is not installed on all Ubuntu images by default)
  wget -qO- https://raw.githubusercontent.com/CesarHGlez13/inutil-music/master/install.sh | bash
  ```

  This downloads the full release tarball, installs the app under `~/.local/`
  (no root required), registers the icon, and creates a desktop entry that
  appears in GNOME / KDE immediately.

- **Ubuntu / Debian — `.deb` package (double-click install):**

  Download `InutilMusic-<version>-linux-amd64.deb` from the
  [latest release](https://github.com/CesarHGlez13/inutil-music/releases/latest)
  and install it with:

  ```bash
  sudo dpkg -i InutilMusic-<version>-linux-amd64.deb
  sudo apt-get install -f    # installs libmpv2 and other missing deps if needed
  ```

  Or open it with Ubuntu's Software Center (double-click the file).

- **Any Linux distro — download & run (no root, no package manager):**

  ```bash
  # Download the tarball
  wget https://github.com/CesarHGlez13/inutil-music/releases/latest/download/inutil_music_linux_x64.tar.gz
  # Extract
  tar -xzf inutil_music_linux_x64.tar.gz
  # Install (places everything under ~/.local, no root needed)
  bash install.sh
  ```

  `libmpv.so.2` is bundled inside `lib/` so the app works on any distro without
  installing any system package. The installer creates `~/.local/bin/inutil-music`,
  the `.desktop` entry, and the app icon automatically.

- **Mac with Apple Silicon (M1, M2, M3, M4, or later):** open `Inutix-Music-<version>-macOS-arm64.pkg`.
- **Mac with an Intel processor:** open `Inutix-Music-<version>-macOS-x64.pkg`.

An `.app` is the complete application and should be opened as one unit, not by entering its `Contents`, `Frameworks`, or `Resources` folders. The `.pkg` installer places `Inutix Music.app` in `/Applications` automatically.

The automated installers are not signed with commercial certificates yet. Windows may show a SmartScreen warning and macOS may show a Gatekeeper warning. Public distribution without those warnings requires a Windows code-signing certificate and Apple Developer ID certificates with notarization.

The version is defined in `pubspec.yaml`, while the text shown inside the application is defined in `lib/core/constants/app_constants.dart`.

## Self-updates and release publishing

Inutix Music compares its own version at start-up and offers the update inside
the app, so a new build reaches every device without the Play Store or a package
manager.

Sources consulted, in order:

1. The manifest URL saved in Settings → Updates.
2. `INUTIL_RELEASE_MANIFEST_URL` in the process environment.
3. `releases/release.json` in the release bucket.
4. The Firestore document `app_config/release` (legacy path, still supported).
5. Any machine on the local network signed in with the same account
   (`GET /api/release`, answered from `~/inutil-releases/release.json`).
6. The last manifest cached on the device.

When none of them answers the app reports the installed version as the latest
one instead of inventing an update it cannot download.

Manifest schema (`release.json`):

```json
{
  "schemaVersion": 1,
  "latestVersion": "2.0.1",
  "mandatory": false,
  "publishedAt": "2026-11-17T04:00:00+00:00",
  "apkDownloadUrl": "/api/releases/app-arm64-v8a-release.apk",
  "linuxDownloadUrl": "/api/releases/inutil_music_linux_x64.tar.gz",
  "androidDownloads": {
    "arm64_v8a": "/api/releases/app-arm64-v8a-release.apk",
    "armeabi_v7a": "/api/releases/app-armeabi-v7a-release.apk",
    "x86_64": "/api/releases/app-x86_64-release.apk"
  },
  "androidDownloadSizes": {"arm64_v8a": 34365793},
  "packageSizeBytes": 34365793,
  "releaseNotes": ["Mejoras de rendimiento y estabilidad."],
  "checksums": {"app-arm64-v8a-release.apk": "6124e1cf…"}
}
```

`androidDownloads` keys are normalized (`arm64-v8a` → `arm64_v8a`) so each
phone downloads only the package matching its ABI.

Publishing a version:

```bash
flutter build apk --release --split-per-abi
flutter build linux --release && bash tool/package_linux.sh
bash tool/publish_release.sh 2.0.1 --dry-run   # prints release.json only
bash tool/publish_release.sh 2.0.1             # local: ~/inutil-releases
bash tool/publish_release.sh 2.0.1 --upload    # Storage + Firestore
```

`--local` (the default) copies the artifacts plus `release.json` into
`~/inutil-releases/`; the running app serves that folder to the rest of the
network on `/api/release` and `/api/releases/<file>`, honouring `Range` requests
so an interrupted download resumes where it stopped. `--github` (the recommended
public channel) publishes the same files as assets of a GitHub Release in
`RELEASE_REPO` (`CesarHGlez13/inutil-music` by default, the same value the app is
compiled with) and then syncs `app_config/release`. `--upload` pushes to Firebase
Storage instead and needs a token for the release project
(`FIREBASE_ACCESS_TOKEN`, or `firebase auth:token --project inutil-music-app`);
both also mirror the manifest into `app_config/release` for devices still on the
old lookup order.

Applying the update:

- Android opens the downloaded APK with `ACTION_VIEW`
  (`REQUEST_INSTALL_PACKAGES`); the playback position is handed over before the
  installer opens and restored afterwards, so updating does not lose the song.
- Linux re-plants the bundle with a detached helper: it waits for the app to
  exit, replaces `data/` and `lib/` (dropping files the new package no longer
  ships), relaunches the new executable and deletes its staging directory.
  `bash tool/test_update_swap.sh` exercises that path against the real tarball.

## Quality

```powershell
dart format .
flutter analyze
flutter test
```

The current test suite covers models, use cases, services, the sleep timer,
TikTok permissions, navigation, favorites, queue behavior and reordering,
external Android audio, iOS platform/login/local-media/export routing, themes,
artwork handling, backup validation, mobile adaptation, and the Windows player
at minimum size.

The release workflow runs formatting, static analysis, and the complete test
suite before any installer job. Pull-request runs are cancelled when a newer
commit supersedes them.

## Files not published

The repository deliberately excludes:

- Builds, APKs, IPAs, EXEs, and distribution packages.
- Local developer tool caches and their auxiliary directories.
- Signing keys, passwords, and local Android configuration files.
- Databases, downloaded music, thumbnails, and user backups.

## Publicar una nueva versión (OTA)

> Complemento operativo de la sección anterior (*Self-updates and release
> publishing*): comandos exactos, modos de `publish_release.sh` y mediciones
> reales de esta máquina.

Guía verificada en esta máquina (Flutter 3.50.0). La app compara
`AppConstants.appVersion` (`lib/core/constants/app_constants.dart:12`, hoy `2.5.16`)
contra `latestVersion` y `minSupportedVersion` del manifiesto Firestore.

### 1. Compilar los artefactos

Android, un APK por ABI con firma de producción oficial (`inutilmusic.keystore`). El flag es `--split-per-abi`; **`--split-abi` no existe**:

```bash
flutter build apk --release --split-per-abi
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
# build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
# build/app/outputs/flutter-apk/app-x86_64-release.apk
```

Linux (el `.tar.gz` es el paquete que la app descomprime y reemplanta dentro de
`~/.local/share/inutil-music`, y el `.deb` es el paquete de instalación para Debian/Ubuntu):

```bash
flutter build linux --release
bash tool/package_linux.sh          # → dist/inutil_music_linux_x64.tar.gz (incluye libmpv e install.sh)
bash packaging/linux/build_packages.sh build/linux/x64/release/bundle 2.5.19 dist # → dist/InutilMusic-2.5.19-linux-amd64.deb
```

`tool/package_linux.sh` guarda el contenido del bundle en la raíz del tar
(`Inutix Music`, `inutil_music`, `data/`, `lib/`, `install.sh`, `THIRD_PARTY_NOTICES.md`),
incrustando automáticamente `lib/libmpv.so.2` para que la app sea 100 % autónoma sin requerir
paquetes adicionales en el sistema.

APK universal opcional (todas las ABIs, ~121 MB): `flutter build apk --release`
genera `app-release.apk`, pero `publish_release.sh` busca
`app-universal-release.apk`, así que hay que copiarlo con ese nombre:

```bash
cp build/app/outputs/flutter-apk/app-release.apk \
   build/app/outputs/flutter-apk/app-universal-release.apk
```

Si no existe, el manifiesto simplemente omite la clave `universal` y
`apkDownloadUrl` apunta al `arm64_v8a` (comprobado con `--dry-run`).

### 2. El manifiesto `release.json`

Esquema exacto (`schemaVersion: 1`) que genera `tool/publish_release.sh`; esta es
la salida real de `bash tool/publish_release.sh 2.5.16 --dry-run`, recortada:

```json
{
  "schemaVersion": 1,
  "latestVersion": "2.5.16",
  "minSupportedVersion": "2.5.16",
  "mandatory": true,
  "publishedAt": "2026-11-17T05:18:43+00:00",
  "apkDownloadUrl": "/api/releases/app-arm64-v8a-release.apk",
  "linuxDownloadUrl": "/api/releases/inutil_music_linux_x64.tar.gz",
  "androidDownloads": {
    "arm64_v8a": "/api/releases/app-arm64-v8a-release.apk",
    "armeabi_v7a": "/api/releases/app-armeabi-v7a-release.apk",
    "x86_64": "/api/releases/app-x86_64-release.apk"
  },
  "androidDownloadSizes": {
    "arm64_v8a": 34365793,
    "armeabi_v7a": 34540327,
    "x86_64": 34703970
  },
  "packageSizeBytes": 34365793,
  "releaseNotes": ["Mejoras de rendimiento y estabilidad."],
  "checksums": {
    "app-arm64-v8a-release.apk": "6124e1cf2b0164a322bbc4c8d71d82b2ec23b4d12c32c87c90b48b2676ec0861"
  }
}
```

| Campo | Para qué sirve |
| --- | --- |
| `schemaVersion` | Versión del esquema; hoy `1`. |
| `latestVersion` | Se compara con `AppConstants.appVersion`. |
| `mandatory` | Si es `true`, el diálogo no ofrece «Ahora no». |
| `publishedAt` | Fecha ISO-8601 UTC; se muestra en el diálogo. |
| `apkDownloadUrl` | APK de respaldo (universal o `arm64_v8a`). |
| `linuxDownloadUrl` | `.tar.gz`/AppImage que reemplanta el instalador de Linux. |
| `androidDownloads` | URL por ABI. Claves **normalizadas con guion bajo**: `arm64_v8a`, `armeabi_v7a`, `x86_64`, `universal`. |
| `androidDownloadSizes` | Bytes por ABI; el diálogo muestra el tamaño real antes de descargar. |
| `packageSizeBytes` | Tamaño del paquete de la plataforma (fallback del tamaño). |
| `releaseNotes` | Lista de líneas; salen en el diálogo (traducibles). |
| `checksums` | SHA-256 por nombre de archivo. |

Orden en que la app busca el manifiesto
(`InutilUpdateService.checkForUpdate`,
[lib/core/firebase/inutil_update_service.dart](file:///home/cesar/Escritorio/alo/inutil_music/lib/core/firebase/inutil_update_service.dart#L374-L426)):

1. La URL escrita en **Ajustes → Actualizaciones** (prefs
   `inutil_release_manifest_url`, línea 335).
2. La variable de entorno `INUTIL_RELEASE_MANIFEST_URL` (línea 339).
3. El manifiesto de la última Release de GitHub,
   `https://github.com/CesarHGlez13/inutil-music/releases/latest/download/release.json`
   (se omite al correr contra el emulador).
4. `https://firebasestorage.googleapis.com/v0/b/<FirebaseConfig.storageBucket>/o/releases%2Frelease.json?alt=media`,
   con el bucket derivado del proyecto: `inutil-music-app.firebasestorage.app`
   (anulable con `--dart-define=FB_STORAGE_BUCKET=…`).
5. El documento Firestore `app_config/release` (línea 329).
6. Un PC de la misma red: `GET /api/release`
   ([firebase_playback_sync_service.dart](file:///home/cesar/Escritorio/alo/inutil_music/lib/core/firebase/firebase_playback_sync_service.dart#L380)).
7. La caché local (prefs `inutil_music_cached_release_v2`).

Mediciones del 2026-11-17 sobre el proyecto real `inutil-music-app`: la clave
pública ya no es un placeholder — `FirebaseConfig.apiKey`
([lib/core/firebase/firebase_config.dart:17](file:///home/cesar/Escritorio/alo/inutil_music/lib/core/firebase/firebase_config.dart#L17))
lleva la clave real del proyecto, leída de `firebase apps:sdkconfig ANDROID`. Con
esa clave, la lectura REST anónima de `app_config/release` devolvía **HTTP 403
`PERMISSION_DENIED`** porque las reglas del repositorio no estaban desplegadas; tras
`firebase deploy --only firestore:rules --project inutil-music-app` devuelve
**HTTP 404** (documento aún no publicado), que es lo que necesita el kill switch
para decidir sin sesión iniciada. El bucket `inutil-music-7b1fa.firebasestorage.app`
que citaban versiones anteriores de esta documentación **no existe**:
`firebase projects:list` sólo expone `inutil-music-app` (número 129744480084) y
`GET https://storage.googleapis.com/storage/v1/b?project=129744480084` no lista
ningún bucket. La propia CLI lo dice al desplegar: *«Firebase Storage has not been
set up on project 'inutil-music-app'. Go to …/storage and click 'Get Started'»*.
Mientras Storage no se aprovisione desde la consola, el canal público es GitHub
Releases (modo `--github`), que no exige credenciales en el teléfono.

### 3. `tool/publish_release.sh`

```bash
bash tool/publish_release.sh <versión> [--notes-file NOTAS.txt] [--local|--github|--upload] [--dry-run]
```

| Modo | Qué hace |
| --- | --- |
| `--local` (por defecto) | Copia los `.apk`/`.tar.gz` y el `release.json` a `~/inutil-releases/` (anulable con `INUTIL_RELEASES_DIR`). Esa carpeta es la que la app de escritorio sirve por HTTP en `/api/release` y `/api/releases/<archivo>`, así que los equipos cercanos se actualizan sin tocar la nube. |
| `--github` | Crea/actualiza la Release `v<versión>` de `RELEASE_REPO` (`CesarHGlez13/inutil-music`) con los artefactos y el `release.json` como assets —descargables sin autenticar— y hace `PATCH` del documento Firestore `app_config/release`. Necesita la CLI `gh` iniciada y, para Firestore, `FIREBASE_ACCESS_TOKEN`. Es el canal público recomendado mientras Cloud Storage no esté aprovisionado. |
| `--upload` | Sube los mismos archivos a `gs://<FB_BUCKET>/releases/…` (por defecto `inutil-music-app.firebasestorage.app`, no hace falta `gsutil`: usa `uploadType=media` con el token) y hace `PATCH` de `app_config/release`. Sin `FIREBASE_ACCESS_TOKEN` sale con código 4. |
| `--dry-run` | Genera e imprime el `release.json` en un directorio temporal y no copia ni sube nada. |

Las notas se leen de `--notes-file` o, si no se indica, de la sección de la
versión en `CHANGELOG.md`. El script exige artefactos ya construidos (código 3 si
no hay nada en `build/app/outputs/flutter-apk` ni en `dist/`) y siempre escribe el
manifiesto en un `mktemp -d`: en el repositorio no queda ningún `release.json`.

Aviso sobre `--upload` medido el 2026-11-17: el CLI está autenticado como
`humbertoglez96@gmail.com`, que **sí** tiene acceso al proyecto `inutil-music-app`
(aparece en `firebase projects:list`), pero el proyecto todavía no tiene Cloud
Storage aprovisionado, así que la subida terminará en 404/403 hasta que Cesar pulse
«Get Started» en la consola. El token OAuth que usa el script se obtiene del
`refresh_token` del CLI (`oauth2.googleapis.com/token`) y caduca a la hora; con él
sí se puede escribir `app_config/release` por la API REST de Firestore, que es lo
que hace el modo `--github`.

### 4. Probar la auto-actualización de Linux

```bash
bash tool/test_update_swap.sh
```

Le extrae el script `sh` embebido al código Dart, monta una instalación falsa en
`~/.local/share/inutil-music-sandbox`, lanza el helper con `setsid` y comprueba
que reemplanta `data/` y `lib/`, relanza y se auto-borra. **Estado verificado
hoy (2026-11-16):** `RESULTADO: PRUEBA SUPERADA` — el script lee el helper de
[lib/core/firebase/inutil_update_service.dart](file:///home/cesar/Escritorio/alo/inutil_music/lib/core/firebase/inutil_update_service.dart)
(`_installLinuxArchiveAndRelaunch`) y confirma el relanzamiento, la convergencia
de `data/` y `lib/` (se retiran los `.so` que el paquete nuevo ya no incluye) y la
limpieza del staging.

### 5. Reglas de Firestore

El fichero del repo es
[firebase/firestore.rules](file:///home/cesar/Escritorio/alo/inutil_music/firebase/firestore.rules)
(no `firestore.rules` en la raíz). El manifiesto vive en `app_config/release`:

```
match /app_config/{document=**} {
  allow read: if true;      // cualquier dispositivo comprueba la versión
  allow write: if isAdmin(); // sólo Cesar publica
}
```

`isAdmin()` exige `request.auth.token.role == 'admin'` o
`request.auth.token.admin == true` (líneas 18-21). Hoy no hay lista de campos, así
que un administrador puede reescribir el documento completo, incluidos
`linuxDownloadUrl` y `androidDownloads`; si se añade una lista explícita deben
figurar esos dos campos más `latestVersion`, `apkDownloadUrl`, `mandatory`,
`publishedAt`, `releaseNotes` y `packageSizeBytes`, porque tanto
`InutilUpdateService.publishRelease` como `publish_release.sh` los escriben en el
mismo `PATCH`. Las claves de `androidDownloads` van con guion bajo
(`arm64_v8a`, `armeabi_v7a`, `x86_64`, `universal`), que es como la app las
normaliza.

### 6. Qué hace la app con ese manifiesto (Android)

1. Al abrir, sin bloquear el arranque, `InutilUpdateService.checkForUpdate()` y
   diálogo no bloqueante («Ahora no» / «Actualizar»).
2. `OtaDownloadManager`
   ([lib/services/app_update/ota_download_manager.dart](file:///home/cesar/Escritorio/alo/inutil_music/lib/services/app_update/ota_download_manager.dart))
   descarga el APK elegido por ABI en `<documentos>/updates/` con cabecera
   `Range`, `.part` + `.meta`: si se corta la red, reanuda donde iba. El progreso
   sólo se pinta dentro de la app (no hay notificación persistente).
3. `AndroidPackageInstaller.installPackage()` abre el instalador con `FileProvider`
   (`${applicationId}.fileprovider`) y `ACTION_VIEW`.
4. `OtaPlaybackResumeStore` guarda pista + posición antes de abrir el instalador
   (TTL 30 min) para reanudar la música al volver, aunque el proceso se reinicie.
