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

final inutilPlaybackSyncProvider = ChangeNotifierProvider<InutilPlaybackSyncService>((
  ref,
) {
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

  // Encaminar una selección al altavoz remoto y sólo silenciar el reproductor
  // local si el encaminamiento llegó de verdad.
  //
  // Si la PC está apagada o no responde, lo único que quedó en el aire es una
  // orden que nadie ejecutó: pausar aquí dejaría el teléfono mudo y la canción
  // no sonaría en ningún lado.
  Future<void> routeSelectionToPeer(PlayerSnapshot snapshot) async {
    final routed = await syncService.playTrackOnPeer(
      trackId: snapshot.trackId!,
      title: snapshot.title ?? 'Canción',
      artist: snapshot.artist ?? 'Inútil Music',
      album: snapshot.album,
      thumbnailUrl: snapshot.thumbnailUrl,
      positionMs: snapshot.position.inMilliseconds,
    );
    if (!routed) return;
    if (!ref.mounted) return;
    await ref.read(playerControllerProvider.notifier).pause(notifyPeer: false);
  }

  // Escuchar cambios del reproductor local para sincronizarlos en LAN y la nube
  ref.listen<AsyncValue<PlayerSnapshot>>(playerControllerProvider, (
    prev,
    next,
  ) {
    final snapshot = next.value;
    if (snapshot == null) return;

    final isPlaying = snapshot.status == PlayerStatus.playing;
    final isRemoteController =
        !InutilPlaybackSyncService.isDesktopHost &&
        !syncService.isCurrentDeviceActive;

    // Si el móvil está en modo control remoto y el track que tiene coincide con el
    // que la PC ya está reproduciendo, este evento es sólo un reflejo de UI del par:
    // no se procesa localmente ni se reenvía a la PC (rompe completamente el ping-pong).
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
    final forcePush =
        prev?.value?.status != snapshot.status ||
        prev?.value?.trackId != snapshot.trackId;

    if (snapshot.trackId != null && snapshot.trackId!.isNotEmpty) {
      // Reproducción en la PC (Spotify Connect):
      // Si la PC ya es el altavoz activo O si está activado "Reproducir siempre en la PC",
      // cualquier canción seleccionada o cambio de pista en el móvil se envía a la PC
      // y el móvil queda como mando a distancia.
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
        // Enviar a la PC y pausar el reproductor del celular LOCALMENTE (sin
        // enviar comando remoto de pausa), pero sólo si la PC aceptó la canción.
        unawaited(routeSelectionToPeer(snapshot));
        return;
      }

      if (isRemoteController) {
        // En modo control remoto, este dispositivo no reproduce el audio
        // ni publica su estado local para evitar sobreescribir la sesión del altavoz (PC)
        // y prevenir bucles de notificación.
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
