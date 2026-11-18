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

final inutilAuthProvider = ChangeNotifierProvider<InutilAuthService>((ref) {
  final service = InutilAuthService.instance;
  return service;
});

/// Respaldo en la nube de playlists, biblioteca y ajustes (users/{uid}/data).
/// Depende del proveedor de la base local para leer/escribir los datos.
final inutilCloudBackupProvider = Provider<InutilCloudBackupService>((ref) {
  final service = InutilCloudBackupService(
    database: ref.watch(databaseServiceProvider),
  );
  ref.onDispose(service.stopAutoSync);
  return service;
});

final inutilPlaybackSyncProvider =
    ChangeNotifierProvider<InutilPlaybackSyncService>((ref) {
  final syncService = InutilPlaybackSyncService.instance;

  // Registrar callback para ejecutar comandos remotos que vengan de otro dispositivo (PC o celular)
  syncService.onRemoteCommandReceived = (commandType, param) async {
    final notifier = ref.read(playerControllerProvider.notifier);
    switch (commandType) {
      case 'play':
      case 'resume':
        await notifier.resume();
        break;
      case 'pause':
        await notifier.pause();
        break;
      case 'toggle':
        await notifier.togglePlayPause();
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
      case 'playTrack':
        if (param is Map<String, dynamic>) {
          final trackId = param['trackId'] as String? ?? '';
          final title = param['title'] as String? ?? '';
          final artist = param['artist'] as String? ?? '';
          final album = param['album'] as String?;
          final thumbnailUrl = param['thumbnailUrl'] as String?;
          final posMs = param['positionMs'] as int? ?? 0;

          if (trackId.isNotEmpty) {
            final track = TrackInfo(
              id: trackId,
              title: title.isNotEmpty ? title : 'Canción',
              artist: artist.isNotEmpty ? artist : 'Inútil Music',
              url: 'https://music.youtube.com/watch?v=$trackId',
              thumbnailUrl: thumbnailUrl,
              album: album,
            );
            await notifier.playRemote(track);
            if (posMs > 0) {
              await notifier.seek(Duration(milliseconds: posMs));
            }
          }
        }
        break;
    }
  };

  // Escuchar cambios del reproductor local para sincronizarlos en LAN y la nube
  ref.listen<AsyncValue<PlayerSnapshot>>(playerControllerProvider, (prev, next) {
    final snapshot = next.value;
    if (snapshot == null) return;

    final isPlaying = snapshot.status == PlayerStatus.playing;
    InutilWrappedService.instance.recordPlaybackTick(
      trackId: snapshot.trackId,
      title: snapshot.title,
      artist: snapshot.artist,
      thumbnailUrl: snapshot.thumbnailUrl,
      positionMs: snapshot.position.inMilliseconds,
      isPlaying: isPlaying,
    );
    final forcePush = prev?.value?.status != snapshot.status ||
        prev?.value?.trackId != snapshot.trackId;

    if (snapshot.trackId != null && snapshot.trackId!.isNotEmpty) {
      // Reproducción automática en la PC: si el móvil arranca una canción y hay
      // un PC con la misma cuenta encendido, la canción suena en la PC y el
      // móvil queda como mando a distancia.
      final shouldRouteToPeer =
          syncService.autoPlayOnPc &&
          syncService.autoPairedPeer != null &&
          !InutilPlaybackSyncService.isDesktopHost &&
          !syncService.isPlaybackRouteSuppressed &&
          forcePush &&
          isPlaying &&
          syncService.isCurrentDeviceActive;

      if (shouldRouteToPeer) {
        // Enviar a la PC y pausar el reproductor del celular
        unawaited(
          syncService.playTrackOnPeer(
            trackId: snapshot.trackId!,
            title: snapshot.title ?? 'Canción',
            artist: snapshot.artist ?? 'Inútil Music',
            album: snapshot.album,
            thumbnailUrl: snapshot.thumbnailUrl,
            positionMs: snapshot.position.inMilliseconds,
          ),
        );
        unawaited(ref.read(playerControllerProvider.notifier).pause());
        return;
      }

      unawaited(
        syncService.notifyPlaybackProgress(
          trackId: snapshot.trackId!,
          title: snapshot.title ?? 'Canción sin título',
          artist: snapshot.artist ?? 'Inútil Music',
          album: snapshot.album,
          thumbnailUrl: snapshot.thumbnailUrl,
          positionMs: snapshot.position.inMilliseconds,
          durationMs: snapshot.duration?.inMilliseconds ?? 0,
          isPlaying: isPlaying,
          force: forcePush,
        ),
      );
    }
  });

  return syncService;
});
