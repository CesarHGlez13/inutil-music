import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/firebase/firebase_auth_service.dart';
import '../../../../core/firebase/firebase_sync_providers.dart';
import '../../../../core/platform/app_platform.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../services/player/player_service.dart';
import '../../../../services/spotify_canvas/spotify_canvas_resolver.dart';
import '../providers/music_providers.dart';
import '../providers/playback_artwork_provider.dart';
import '../providers/spotify_canvas_provider.dart';
import '../providers/video_preview_provider.dart';
import 'inutil_connect_sheet.dart';
import 'now_playing_equalizer.dart';
import 'source_image.dart';
import 'spotify_canvas_video.dart';

/// Panel lateral derecho "Ahora suena" estilo Spotify 2026 para escritorio.
///
/// Muestra el vídeo vertical Spotify Canvas 9:16 (o portada animada con
/// iluminación ambiental) mientras el usuario navega por Inicio, Búsqueda o
/// Biblioteca, junto con la tarjeta activa de Inutix Connect y las siguientes
/// canciones en la cola.
class DesktopNowPlayingRail extends ConsumerWidget {
  const DesktopNowPlayingRail({
    required this.spotifyCanvasEnabled,
    required this.animatedArtworkEnabled,
    required this.onOpenPlayer,
    required this.onOpenLyrics,
    required this.onClose,
    super.key,
  });

  final bool spotifyCanvasEnabled;
  final bool animatedArtworkEnabled;
  final VoidCallback onOpenPlayer;
  final VoidCallback onOpenLyrics;
  final VoidCallback onClose;

  static const Color _spotifyGreen = Color(0xFF1ED760);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final surfaceMode = AppColors.surfaceBackgroundModeFor(context);
    final transparent = surfaceMode.usesBackdrop;
    final snapshot = ref.watch(playerControllerProvider).value;
    if (snapshot == null) {
      return const SizedBox.shrink();
    }

    final artwork = ref.watch(playbackArtworkProvider);
    final artworkSource = artwork.source ?? snapshot.thumbnailUrl;
    final artworkFallback = artwork.fallback;
    final syncService = ref.watch(inutilPlaybackSyncProvider);
    final queue = ref.watch(playbackQueueProvider);
    final isPlaying = snapshot.status == PlayerStatus.playing;

    final remoteVideoAllowed =
        snapshot.status != PlayerStatus.idle &&
        snapshot.status != PlayerStatus.failed &&
        AppPlatform.supportsRemoteArtworkVideo;
    final canvasTrack = SpotifyCanvasTrack(
      snapshot.title ?? '',
      snapshot.artist ?? '',
      snapshot.duration ?? Duration.zero,
    );
    final spotifyCanvasAsync =
        (spotifyCanvasEnabled || animatedArtworkEnabled) && remoteVideoAllowed
        ? ref.watch(spotifyCanvasUrlProvider(canvasTrack))
        : null;
    final spotifyCanvasUrl = spotifyCanvasAsync?.value;
    final fallbackVideoPreviewUrl =
        spotifyCanvasUrl == null &&
            !(spotifyCanvasAsync?.isLoading ?? false) &&
            (spotifyCanvasEnabled || animatedArtworkEnabled) &&
            remoteVideoAllowed
        ? ref
              .watch(
                trackVideoPreviewProvider((
                  title: snapshot.title ?? '',
                  artist: snapshot.artist ?? '',
                  videoId: snapshot.trackId,
                )),
              )
              .value
              ?.videoUrl
        : null;
    final effectiveCanvasUrl = spotifyCanvasUrl ?? fallbackVideoPreviewUrl;

    final remoteSpeakerName = syncService.activeRemoteSpeakerName;
    final lanPeerCount = syncService.connectTargets
        .where((peer) => !peer.isCloudOnly)
        .length;
    final hasLanPeer = lanPeerCount > 0;
    final activeDeviceLabel =
        remoteSpeakerName ?? InutilAuthService.instance.deviceName;
    final connectSubtitle = remoteSpeakerName != null
        ? (hasLanPeer
              ? 'Controlando en red local · instantáneo'
              : 'Controlando a distancia · nube')
        : (hasLanPeer
              ? 'Sonando en este equipo · $lanPeerCount en red local'
              : 'Sonando en este equipo · Inutix Connect');

    final upcomingEntries = <({int index, PlaybackQueueEntry entry})>[];
    if (queue.entries.isNotEmpty) {
      final start = (queue.currentIndex + 1).clamp(0, queue.entries.length);
      for (
        var i = start;
        i < queue.entries.length && upcomingEntries.length < 4;
        i++
      ) {
        upcomingEntries.add((index: i, entry: queue.entries[i]));
      }
    } else if (syncService.remoteSession != null &&
        syncService.remoteSession!.queue.isNotEmpty) {
      final remoteQueue = syncService.remoteSession!.queue;
      final start = (syncService.remoteSession!.queueIndex + 1).clamp(
        0,
        remoteQueue.length,
      );
      for (
        var i = start;
        i < remoteQueue.length && upcomingEntries.length < 4;
        i++
      ) {
        final raw = remoteQueue[i];
        upcomingEntries.add((
          index: i,
          entry: PlaybackQueueEntry(
            id: (raw['id'] ?? '').toString(),
            title: (raw['title'] ?? 'Canción').toString(),
            artist: (raw['artist'] ?? 'Inutix Music').toString(),
            album: raw['album']?.toString(),
            thumbnailUrl: raw['thumbnailUrl']?.toString(),
            isRemote: true,
          ),
        ));
      }
    }

    final railSurface = Container(
      key: const ValueKey('desktop-now-playing-rail'),
      width: 316,
      decoration: BoxDecoration(
        color: AppColors.surfaceChromeFor(
          context,
          accentModeAlpha: 0.92,
          transparentDarkAlpha: 0.36,
          transparentLightAlpha: 0.44,
          accentTintAlpha: transparent ? 0.06 : 0.08,
        ),
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        left: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
              child: Row(
                children: [
                  if (isPlaying)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: NowPlayingEqualizer(
                        isPlaying: true,
                        width: 22,
                        height: 14,
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        size: 17,
                        color: _spotifyGreen,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      remoteSpeakerName ?? 'Ahora suena',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('desktop-now-playing-lyrics-button'),
                    tooltip: 'Letras',
                    visualDensity: VisualDensity.compact,
                    onPressed: onOpenLyrics,
                    icon: const Icon(Icons.lyrics_outlined, size: 19),
                  ),
                  IconButton(
                    key: const ValueKey('desktop-now-playing-expand-button'),
                    tooltip: 'Abrir reproductor completo',
                    visualDensity: VisualDensity.compact,
                    onPressed: onOpenPlayer,
                    icon: const Icon(Icons.open_in_full_rounded, size: 18),
                  ),
                  IconButton(
                    key: const ValueKey('desktop-now-playing-close-button'),
                    tooltip: 'Ocultar vista Ahora suena',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 16),
                children: [
                  // Tarjeta vertical 9:16 Spotify Canvas 2026
                  GestureDetector(
                    key: const ValueKey('desktop-now-playing-canvas-card'),
                    onTap: onOpenPlayer,
                    child: Container(
                      height: 368,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: const Color(0xFF101216),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.36),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (artworkSource != null &&
                              artworkSource.trim().isNotEmpty)
                            SourceImage(
                              source: artworkSource,
                              fallbackSource: artworkFallback,
                              fit: BoxFit.cover,
                              fallback: const _ArtworkFallback(),
                            )
                          else
                            const _ArtworkFallback(),
                          if (effectiveCanvasUrl != null)
                            SpotifyCanvasVideo(
                              key: ValueKey(
                                'desktop-rail-canvas-$effectiveCanvasUrl',
                              ),
                              url: effectiveCanvasUrl,
                              isPlaying: isPlaying,
                              identity: snapshot.trackId ?? snapshot.title,
                            ),
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.56),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.16),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    effectiveCanvasUrl != null
                                        ? Icons.movie_filter_rounded
                                        : Icons.album_rounded,
                                    size: 13,
                                    color: _spotifyGreen,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    effectiveCanvasUrl != null
                                        ? 'CANVAS 2026'
                                        : 'ALTA FIDELIDAD',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.2,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                44,
                                16,
                                16,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.72),
                                    Colors.black.withValues(alpha: 0.92),
                                  ],
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    snapshot.title ?? 'Sin reproducción',
                                    key: const ValueKey(
                                      'desktop-now-playing-title',
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      height: 1.18,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    snapshot.artist ?? 'Inutix Music',
                                    key: const ValueKey(
                                      'desktop-now-playing-artist',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.78,
                                      ),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (snapshot.album != null &&
                                      snapshot.album!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      snapshot.album!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.54,
                                        ),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Tarjeta Inutix Connect (Spotify Connect Parity)
                  InkWell(
                    key: const ValueKey('desktop-now-playing-connect-card'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => InutilConnectSheet.show(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: (remoteSpeakerName != null || hasLanPeer)
                            ? _spotifyGreen.withValues(alpha: 0.12)
                            : AppColors.cardSurfaceFor(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (remoteSpeakerName != null || hasLanPeer)
                              ? _spotifyGreen.withValues(alpha: 0.38)
                              : AppColors.cardBorderFor(context),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _spotifyGreen.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Icon(
                              Icons.devices_rounded,
                              color: _spotifyGreen,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activeDeviceLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color:
                                        (remoteSpeakerName != null ||
                                            hasLanPeer)
                                        ? _spotifyGreen
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  connectSubtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11.2,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: _spotifyGreen,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (upcomingEntries.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      key: const ValueKey('desktop-now-playing-up-next'),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurfaceFor(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.cardBorderFor(context),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Siguiente en la cola',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                onPressed: onOpenPlayer,
                                child: const Text(
                                  'Ver cola',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          for (final item in upcomingEntries)
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => unawaited(
                                ref
                                    .read(playerControllerProvider.notifier)
                                    .playQueueIndex(item.index),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: Colors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child:
                                          item.entry.thumbnailUrl != null &&
                                              item.entry.thumbnailUrl!
                                                  .trim()
                                                  .isNotEmpty
                                          ? SourceImage(
                                              source: item.entry.thumbnailUrl!,
                                              fit: BoxFit.cover,
                                              fallback: const Icon(
                                                Icons.music_note_rounded,
                                                size: 18,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.music_note_rounded,
                                              size: 18,
                                            ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.entry.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12.8,
                                                ),
                                          ),
                                          Text(
                                            item.entry.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  fontSize: 11.3,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: transparent ? 18 : 28,
          sigmaY: transparent ? 18 : 28,
        ),
        child: railSurface,
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2230), Color(0xFF0D1017)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 56,
          color: Colors.white.withValues(alpha: 0.24),
        ),
      ),
    );
  }
}
