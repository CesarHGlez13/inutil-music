import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../features/music/domain/entities/track_info.dart';
import '../../features/music/presentation/providers/music_providers.dart';
import '../../services/player/player_service.dart';
import 'firebase_auth_service.dart';
import 'firebase_playback_sync_service.dart';
import 'inutil_cloud_backup_service.dart';
import 'inutil_wrapped_service.dart';

// `InutilAuthService.instance` es un singleton global. `ChangeNotifierProvider`
// desecha al `ChangeNotifier` que crea cuando su contenedor se descarta, así
// que el contenedor siguiente (otro `ProviderScope`, un hot reload en debug,
// o el siguiente `ProviderContainer` de una prueba) hereda un singleton ya
// muerto y `ref.watch` lanza `ProviderException … used after being disposed`.
// `disposeNotifier: false` le quita a Riverpod la propiedad del ciclo de vida.
final inutilAuthProvider = ChangeNotifierProvider<InutilAuthService>((ref) {
  final service = InutilAuthService.instance;
  return service;
}, disposeNotifier: false);

/// Respaldo en la nube de playlists, biblioteca y ajustes (users/{uid}/data).
/// Depende del proveedor de la base local para leer/escribir los datos.
final inutilCloudBackupProvider = Provider<InutilCloudBackupService>((ref) {
  final service = InutilCloudBackupService(
    database: ref.watch(databaseServiceProvider),
  );
  ref.onDispose(service.stopAutoSync);
  return service;
});

final inutilPlaybackSyncProvider = ChangeNotifierProvider<InutilPlaybackSyncService>(
  (ref) {
    final syncService = InutilPlaybackSyncService.instance;

    // Registrar callback para ejecutar comandos remotos que vengan de otro dispositivo (PC o celular)
    syncService.onRemoteCommandReceived = (commandType, param) async {
      final notifier = ref.read(playerControllerProvider.notifier);
      final currentSnap = ref.read(playerServiceProvider).currentSnapshot;
      Future<bool> hydrateIdleSessionIfNeeded() async {
        if (currentSnap.status != PlayerStatus.idle &&
            (currentSnap.trackId?.trim().isNotEmpty ?? false)) {
          return false;
        }
        final session = syncService.remoteSession;
        if (session == null || session.trackId.trim().isEmpty) {
          return false;
        }
        final track = TrackInfo(
          id: session.trackId,
          title: session.title.isNotEmpty ? session.title : 'Canción',
          artist: session.artist.isNotEmpty ? session.artist : 'Inutix Music',
          url: 'https://music.youtube.com/watch?v=${session.trackId}',
          thumbnailUrl: session.thumbnailUrl.isEmpty
              ? null
              : session.thumbnailUrl,
          album: session.album,
          duration: session.durationMs > 0
              ? Duration(milliseconds: session.durationMs)
              : null,
        );
        final queueTracks = <TrackInfo>[];
        for (final item in session.queue) {
          final parsed = _trackInfoFromRemoteMap(item);
          if (parsed != null) queueTracks.add(parsed);
        }
        await notifier.playRemote(
          track,
          queue: queueTracks.isNotEmpty ? queueTracks : null,
        );
        final nearEnd =
            session.durationMs > 0 &&
            session.positionMs >= session.durationMs - 2500;
        if (session.positionMs > 0 && !nearEnd) {
          await notifier.seek(Duration(milliseconds: session.positionMs));
        }
        return true;
      }

      switch (commandType) {
        case 'play':
        case 'resume':
          if (!await hydrateIdleSessionIfNeeded()) {
            await notifier.resume();
          }
          break;
        case 'pause':
          await notifier.pause();
          break;
        case 'toggle':
          if (!await hydrateIdleSessionIfNeeded()) {
            await notifier.togglePlayPause();
          }
          break;
        case 'next':
          await notifier.playNext();
          break;
        case 'previous':
          await notifier.playPrevious();
          break;
        case 'seek':
          if (param != null) {
            final ms = int.tryParse(param.toString()) ?? 0;
            await notifier.seek(Duration(milliseconds: ms));
          }
          break;
        case 'setVolume':
          if (param != null) {
            final vol = double.tryParse(param.toString());
            if (vol != null) {
              await notifier.setVolume(vol.clamp(0.0, 1.0));
            }
          }
          break;
        case 'setShuffle':
          if (param != null) {
            final enabled = param == true || param.toString() == 'true';
            notifier.setShuffleEnabled(enabled, fromRemoteCommand: true);
          }
          break;
        case 'setRepeat':
          if (param != null) {
            final raw = param.toString().trim().toLowerCase();
            final mode = switch (raw) {
              'all' => PlaybackRepeatMode.all,
              'one' => PlaybackRepeatMode.one,
              _ => PlaybackRepeatMode.off,
            };
            notifier.setRepeatMode(mode, fromRemoteCommand: true);
          }
          break;
        case 'addToQueue':
          if (param is Map<String, dynamic>) {
            final track = _trackInfoFromRemoteMap(param);
            if (track != null) {
              notifier.enqueueRemoteNext(track);
            }
          }
          break;
        case 'playTrack':
          if (param is Map<String, dynamic>) {
            final trackId = param['trackId'] as String? ?? '';
            final title = param['title'] as String? ?? '';
            final artist = param['artist'] as String? ?? '';
            final album = param['album'] as String?;
            final thumbnailUrl = param['thumbnailUrl'] as String?;
            final posMs = param['positionMs'] is int
                ? param['positionMs'] as int
                : int.tryParse(param['positionMs']?.toString() ?? '') ?? 0;
            final durationMs = param['durationMs'] is int
                ? param['durationMs'] as int
                : int.tryParse(param['durationMs']?.toString() ?? '') ?? 0;

            if (trackId.isNotEmpty) {
              final rawQueue = param['queue'];
              final queueTracks = <TrackInfo>[];
              if (rawQueue is List) {
                for (final item in rawQueue) {
                  if (item is Map) {
                    final parsed = _trackInfoFromRemoteMap(
                      Map<String, dynamic>.from(item),
                    );
                    if (parsed != null) queueTracks.add(parsed);
                  }
                }
              }
              final rawQueueIndex = param['queueIndex'];
              final initialQueueIndex = rawQueueIndex is num
                  ? rawQueueIndex.toInt()
                  : null;
              final explicitUrl = (param['url'] ?? '').toString().trim();
              String? matchedQueueUrl;
              if (initialQueueIndex != null &&
                  initialQueueIndex >= 0 &&
                  initialQueueIndex < queueTracks.length &&
                  queueTracks[initialQueueIndex].id == trackId) {
                matchedQueueUrl = queueTracks[initialQueueIndex].url;
              } else {
                for (final candidate in queueTracks) {
                  if (candidate.id == trackId && candidate.url.isNotEmpty) {
                    matchedQueueUrl = candidate.url;
                    break;
                  }
                }
              }
              final canonicalUrl = explicitUrl.isNotEmpty
                  ? explicitUrl
                  : (matchedQueueUrl != null && matchedQueueUrl.isNotEmpty
                        ? matchedQueueUrl
                        : 'https://music.youtube.com/watch?v=$trackId');
              final track = TrackInfo(
                id: trackId,
                title: title.isNotEmpty ? title : 'Canción',
                artist: artist.isNotEmpty ? artist : 'Inutix Music',
                url: canonicalUrl,
                thumbnailUrl: thumbnailUrl,
                album: album,
                duration: durationMs > 0
                    ? Duration(milliseconds: durationMs)
                    : null,
              );
              if (param['shuffleEnabled'] is bool) {
                notifier.setShuffleEnabled(
                  param['shuffleEnabled'] as bool,
                  fromRemoteCommand: true,
                );
              }
              if (param['repeatMode'] is String) {
                final raw = (param['repeatMode'] as String)
                    .trim()
                    .toLowerCase();
                notifier.setRepeatMode(switch (raw) {
                  'all' => PlaybackRepeatMode.all,
                  'one' => PlaybackRepeatMode.one,
                  _ => PlaybackRepeatMode.off,
                }, fromRemoteCommand: true);
              }
              await notifier.playRemote(
                track,
                queue: queueTracks.isNotEmpty ? queueTracks : null,
                initialQueueIndex: initialQueueIndex,
              );
              if (posMs > 0) {
                await notifier.seek(Duration(milliseconds: posMs));
              }
            }
          }
          break;
      }
    };

    // Encaminar una selección al altavoz remoto y sólo silenciar el reproductor
    // local si el encaminamiento llegó de verdad.
    Future<void> routeSelectionToPeer(PlayerSnapshot snapshot) async {
      final controller = ref.read(playerControllerProvider.notifier);
      final exported = controller.exportCompactRemoteQueue();
      final routed = await syncService.playTrackOnPeer(
        trackId: snapshot.trackId!,
        title: snapshot.title ?? 'Canción',
        artist: snapshot.artist ?? 'Inutix Music',
        album: snapshot.album,
        thumbnailUrl: snapshot.thumbnailUrl,
        positionMs: snapshot.position.inMilliseconds,
        durationMs: snapshot.duration?.inMilliseconds ?? 0,
        queue: exported.items,
        queueIndex: exported.index,
        volume: snapshot.volume,
        shuffleEnabled: snapshot.shuffleEnabled,
        repeatMode: snapshot.repeatMode.name,
      );
      if (!routed) return;
      if (!ref.mounted) return;
      await controller.pause(notifyPeer: false);
    }

    // Escuchar cambios del reproductor local para sincronizarlos en LAN y la nube
    ref.listen<AsyncValue<PlayerSnapshot>>(playerControllerProvider, (
      prev,
      next,
    ) {
      final snapshot = next.value;
      if (snapshot == null) return;

      final isPlaying =
          snapshot.status == PlayerStatus.playing ||
          (snapshot.status == PlayerStatus.loading &&
              snapshot.playWhenReady == true);
      final isRemoteController = !syncService.isCurrentDeviceActive;

      // Si este equipo está en modo control remoto y el track coincide con el
      // que el altavoz remoto ya está reproduciendo, este evento es sólo un
      // reflejo de UI del par: no se procesa localmente ni se reenvía.
      final isMirroringRemoteTrack =
          isRemoteController &&
          snapshot.trackId != null &&
          snapshot.trackId == syncService.remoteSession?.trackId;

      if (isMirroringRemoteTrack) {
        return;
      }

      if (!isRemoteController) {
        InutilWrappedService.instance.recordPlaybackTick(
          trackId: snapshot.trackId,
          title: snapshot.title,
          artist: snapshot.artist,
          thumbnailUrl: snapshot.thumbnailUrl,
          positionMs: snapshot.position.inMilliseconds,
          isPlaying: isPlaying,
        );
      }
      final prevSnap = prev?.value;
      final forcePush =
          prevSnap?.status != snapshot.status ||
          prevSnap?.trackId != snapshot.trackId ||
          prevSnap?.shuffleEnabled != snapshot.shuffleEnabled ||
          prevSnap?.repeatMode != snapshot.repeatMode ||
          ((prevSnap?.volume ?? snapshot.volume) - snapshot.volume).abs() >=
              0.04;

      if (snapshot.trackId != null && snapshot.trackId!.isNotEmpty) {
        final shouldRouteToPeer =
            InutilPlaybackSyncService.shouldRoutePlaybackToPeer(
              autoPlayOnPc: syncService.autoPlayOnPc,
              isCurrentDeviceActive: syncService.isCurrentDeviceActive,
              remoteActiveDeviceId:
                  syncService.remoteSession?.activeDeviceId ?? '',
              hasTargetPeer:
                  syncService.autoPairedPeer != null ||
                  syncService.connectTargets.any((p) => p.isHost),
              isDesktopHost: InutilPlaybackSyncService.isDesktopHost,
              isPlaybackRouteSuppressed: syncService.isPlaybackRouteSuppressed,
              forcePush: forcePush,
              isPlaying: isPlaying,
              isRemoteSnapshot: isMirroringRemoteTrack,
            );

        if (shouldRouteToPeer) {
          unawaited(routeSelectionToPeer(snapshot));
          return;
        }

        if (isRemoteController) {
          return;
        }

        final controller = ref.read(playerControllerProvider.notifier);
        final exported = controller.exportCompactRemoteQueue();
        unawaited(
          syncService.notifyPlaybackProgress(
            trackId: snapshot.trackId!,
            title: snapshot.title ?? 'Canción sin título',
            artist: snapshot.artist ?? 'Inutix Music',
            album: snapshot.album,
            thumbnailUrl: snapshot.thumbnailUrl,
            positionMs: snapshot.position.inMilliseconds,
            durationMs: snapshot.duration?.inMilliseconds ?? 0,
            isPlaying: isPlaying,
            volume: snapshot.volume,
            shuffleEnabled: snapshot.shuffleEnabled,
            repeatMode: snapshot.repeatMode.name,
            queue: exported.items,
            queueIndex: exported.index,
            force: forcePush,
          ),
        );
      }
    });

    return syncService;
  },
  // Mismo caso que `inutilAuthProvider`: `InutilPlaybackSyncService.instance` es
  // un singleton global que comparten el reproductor, la hoja Connect y el
  // respaldo en la nube, así que este proveedor no debe ser su dueño. Sin
  // `disposeNotifier: false` el primer contenedor que se descarta deja el
  // singleton desechado y todo contenedor posterior lo encuentra muerto; en
  // Windows eso se veía como `ProviderException … A InutilPlaybackSyncService
  // was used after being disposed` dentro de `_SpotifyFullscreenCanvasPlayer.build`
  // (`player_canvas_layout_test.dart`, que GitHub Actions sólo ejecuta en el
  // runner de Windows). Medido en
  // `test/core/firebase/shared_singleton_dispose_test.dart`.
  disposeNotifier: false,
);

TrackInfo? _trackInfoFromRemoteMap(Map<String, dynamic> raw) {
  final id = (raw['id'] ?? raw['trackId'] ?? '').toString().trim();
  if (id.isEmpty) return null;
  final title = (raw['title'] ?? '').toString().trim();
  final artist = (raw['artist'] ?? '').toString().trim();
  final album = (raw['album'] ?? '').toString().trim();
  final thumb = (raw['thumbnailUrl'] ?? '').toString().trim();
  final durationMs = raw['durationMs'] is int
      ? raw['durationMs'] as int
      : int.tryParse(raw['durationMs']?.toString() ?? '') ?? 0;
  final url = (raw['url'] ?? '').toString().trim();
  return TrackInfo(
    id: id,
    title: title.isNotEmpty ? title : 'Canción',
    artist: artist.isNotEmpty ? artist : 'Inutix Music',
    album: album.isEmpty ? null : album,
    thumbnailUrl: thumb.isEmpty ? null : thumb,
    url: url.isNotEmpty ? url : 'https://music.youtube.com/watch?v=$id',
    duration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
  );
}
