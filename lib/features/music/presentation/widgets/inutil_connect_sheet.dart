import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/firebase/firebase_playback_sync_service.dart';
import '../../../../core/firebase/firebase_sync_providers.dart';
import '../../../../services/player/player_service.dart';
import '../../domain/entities/track_info.dart';
import '../providers/listening_room_providers.dart';
import '../providers/music_providers.dart';
import 'listening_room_sheet.dart';

/// Modal estilo Spotify Connect para control de reproducción, volumen remoto y
/// transferencia instantánea entre cualquier equipo con la misma cuenta.
class InutilConnectSheet extends ConsumerWidget {
  const InutilConnectSheet({super.key});

  static const _spotifyGreen = Color(0xFF1DB954);

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const InutilConnectSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncService = ref.watch(inutilPlaybackSyncProvider);
    final authService = ref.watch(inutilAuthProvider);
    final playerMeta = ref.watch(
      playerControllerProvider.select((player) {
        final snapshot = player.value;
        return (
          trackId: snapshot?.trackId,
          title: snapshot?.title,
          artist: snapshot?.artist,
          album: snapshot?.album,
          thumbnailUrl: snapshot?.thumbnailUrl,
          durationMs: snapshot?.duration?.inMilliseconds ?? 0,
          volume: snapshot?.volume ?? 1.0,
          shuffleEnabled: snapshot?.shuffleEnabled ?? false,
          repeatMode: snapshot?.repeatMode ?? PlaybackRepeatMode.off,
        );
      }),
    );

    final remoteSession = syncService.remoteSession;
    final isLocalActive = syncService.isCurrentDeviceActive;
    final targets = syncService.connectTargets;
    final activeRemoteId = !isLocalActive
        ? (remoteSession?.activeDeviceId ?? '')
        : '';
    LanDevicePeer? activeRemotePeer;
    if (activeRemoteId.isNotEmpty) {
      for (final peer in targets) {
        if (peer.deviceId == activeRemoteId) {
          activeRemotePeer = peer;
          break;
        }
      }
    }
    final otherPeers = targets
        .where((peer) => peer.deviceId != activeRemotePeer?.deviceId)
        .toList(growable: false);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cardSurface = colors.surfaceContainerLow.withValues(alpha: 0.92);
    final cardBorder = colors.outlineVariant.withValues(alpha: 0.45);

    final isMobilePlatform =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.fuchsia;
    final thisDeviceLabel = switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => 'Este teléfono',
      TargetPlatform.windows => 'Esta PC',
      _ => 'Este ordenador',
    };

    final sessionTitle =
        (remoteSession != null && remoteSession.title.isNotEmpty)
        ? remoteSession.title
        : playerMeta.title ?? '';
    final sessionArtist =
        (remoteSession != null && remoteSession.artist.isNotEmpty)
        ? remoteSession.artist
        : playerMeta.artist ?? '';
    final hasSession = sessionTitle.isNotEmpty;
    final sessionLine = hasSession
        ? (sessionArtist.isEmpty
              ? sessionTitle
              : '$sessionTitle — $sessionArtist')
        : null;
    final sessionBadge = !hasSession
        ? null
        : ((remoteSession?.isPlaying ?? false) ? 'Reproduciendo' : 'En pausa');

    final activeTitle = isLocalActive
        ? thisDeviceLabel
        : (activeRemotePeer?.deviceName ??
              syncService.activeRemoteSpeakerName ??
              thisDeviceLabel);
    final activePlatform = isLocalActive
        ? defaultTargetPlatform.name
        : (activeRemotePeer?.platform ??
              remoteSession?.activeDevicePlatform ??
              'desktop');
    final activeAccent = isLocalActive ? colors.primary : _spotifyGreen;
    final remoteVolume = (remoteSession?.volume ?? playerMeta.volume).clamp(
      0.0,
      1.0,
    );

    Future<void> transferToThisDevice() async {
      final nav = Navigator.maybeOf(context);
      final controller = ref.read(playerControllerProvider.notifier);
      if (remoteSession == null || remoteSession.trackId.isEmpty) {
        await syncService.transferPlaybackToThisDevice(
          trackId: playerMeta.trackId ?? '',
          title: playerMeta.title ?? '',
          artist: playerMeta.artist ?? '',
          album: playerMeta.album,
          thumbnailUrl: playerMeta.thumbnailUrl,
          positionMs: 0,
          durationMs: playerMeta.durationMs,
          isPlaying: false,
        );
        nav?.pop();
        return;
      }

      final posMs = remoteSession.estimatedPositionMs;
      final track = TrackInfo(
        id: remoteSession.trackId,
        title: remoteSession.title.isNotEmpty
            ? remoteSession.title
            : 'Canción activa',
        artist: remoteSession.artist.isNotEmpty
            ? remoteSession.artist
            : 'Inutix Music',
        album: remoteSession.album.isEmpty ? null : remoteSession.album,
        thumbnailUrl: remoteSession.thumbnailUrl.isEmpty
            ? null
            : remoteSession.thumbnailUrl,
        url: 'https://music.youtube.com/watch?v=${remoteSession.trackId}',
        duration: remoteSession.durationMs > 0
            ? Duration(milliseconds: remoteSession.durationMs)
            : null,
      );

      final transferredQueue = <TrackInfo>[];
      for (final raw in remoteSession.queue) {
        final id = (raw['id'] ?? raw['trackId'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final durMs = raw['durationMs'] is int
            ? raw['durationMs'] as int
            : int.tryParse(raw['durationMs']?.toString() ?? '') ?? 0;
        transferredQueue.add(
          TrackInfo(
            id: id,
            title: (raw['title'] ?? 'Canción').toString(),
            artist: (raw['artist'] ?? 'Inutix Music').toString(),
            album: (raw['album'] as String?)?.isNotEmpty == true
                ? raw['album'] as String
                : null,
            thumbnailUrl: (raw['thumbnailUrl'] as String?)?.isNotEmpty == true
                ? raw['thumbnailUrl'] as String
                : null,
            url: (raw['url'] as String?)?.isNotEmpty == true
                ? raw['url'] as String
                : 'https://music.youtube.com/watch?v=$id',
            duration: durMs > 0 ? Duration(milliseconds: durMs) : null,
          ),
        );
      }

      await syncService.transferPlaybackToThisDevice(
        trackId: remoteSession.trackId,
        title: remoteSession.title,
        artist: remoteSession.artist,
        album: remoteSession.album,
        thumbnailUrl: remoteSession.thumbnailUrl,
        positionMs: posMs,
        durationMs: remoteSession.durationMs,
        isPlaying: true,
        volume: remoteSession.volume,
        shuffleEnabled: remoteSession.shuffleEnabled,
        repeatMode: remoteSession.repeatMode,
        queue: remoteSession.queue,
        queueIndex: remoteSession.queueIndex,
      );
      await controller.playRemote(
        track,
        queue: transferredQueue.isNotEmpty ? transferredQueue : null,
      );
      if (posMs > 0) {
        await controller.seek(Duration(milliseconds: posMs));
      }
      nav?.pop();
    }

    Future<void> transferToPeer(LanDevicePeer peer) async {
      final nav = Navigator.maybeOf(context);
      final controller = ref.read(playerControllerProvider.notifier);
      final currentSnap = ref.read(playerControllerProvider).value;
      final trackId =
          (currentSnap?.trackId?.isNotEmpty == true
              ? currentSnap!.trackId
              : null) ??
          (remoteSession?.trackId.isNotEmpty == true
              ? remoteSession!.trackId
              : null);

      if (trackId == null || trackId.isEmpty) {
        syncService.selectPeer(peer);
        nav?.pop();
        return;
      }

      final title =
          currentSnap?.title ??
          (remoteSession?.title.isNotEmpty == true
              ? remoteSession!.title
              : 'Canción');
      final artist =
          currentSnap?.artist ??
          (remoteSession?.artist.isNotEmpty == true
              ? remoteSession!.artist
              : 'Inutix Music');
      final album = currentSnap?.album ?? remoteSession?.album;
      final thumb = currentSnap?.thumbnailUrl ?? remoteSession?.thumbnailUrl;
      final posMs = isLocalActive
          ? (currentSnap?.position.inMilliseconds ?? 0)
          : (remoteSession?.estimatedPositionMs ?? 0);
      final durMs = isLocalActive
          ? (currentSnap?.duration?.inMilliseconds ?? 0)
          : (remoteSession?.durationMs ?? 0);
      final exported = controller.exportCompactRemoteQueue();
      final queueItems = exported.items.isNotEmpty
          ? exported.items
          : (remoteSession?.queue ?? const <Map<String, dynamic>>[]);
      final queueIndex = exported.items.isNotEmpty
          ? exported.index
          : (remoteSession?.queueIndex ?? 0);

      // Si había otro altavoz remoto activo distinto, lo pausamos.
      if (!isLocalActive &&
          activeRemotePeer != null &&
          activeRemotePeer.deviceId != peer.deviceId) {
        unawaited(
          activeRemotePeer.isCloudOnly
              ? syncService.sendCloudCommand(
                  targetDeviceId: activeRemotePeer.deviceId,
                  commandType: 'pause',
                )
              : syncService.sendLanCommand(
                  commandType: 'pause',
                  targetPeer: activeRemotePeer,
                ),
        );
      }

      final ok = await syncService.playTrackOnPeer(
        trackId: trackId,
        title: title,
        artist: artist,
        album: album,
        thumbnailUrl: thumb,
        positionMs: posMs,
        durationMs: durMs,
        queue: queueItems,
        queueIndex: queueIndex,
        shuffleEnabled: playerMeta.shuffleEnabled,
        repeatMode: playerMeta.repeatMode.name,
        targetPeer: peer,
      );
      if (ok && isLocalActive) {
        unawaited(controller.pause(notifyPeer: false));
      }
      nav?.pop();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: cardBorder),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Conectar',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  if (authService.isAuthenticated)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: colors.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        authService.currentUser?.displayName ?? 'Cuenta',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // 1. Altavoz activo actual (estilo Spotify Connect)
              if (authService.isAuthenticated)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: activeAccent.withValues(alpha: 0.55),
                      width: 1.3,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getPlatformIcon(activePlatform),
                            color: activeAccent,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        activeTitle,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              color: isLocalActive
                                                  ? colors.onSurface
                                                  : _spotifyGreen,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.3,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (sessionBadge != null) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: activeAccent.withValues(
                                            alpha: 0.14,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          sessionBadge,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: activeAccent,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  sessionLine ?? 'Nada en reproducción',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: sessionLine == null
                                        ? colors.onSurfaceVariant
                                        : colors.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (!isLocalActive &&
                                    activeRemotePeer != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: activeRemotePeer.isCloudOnly
                                              ? colors.primary
                                              : _spotifyGreen,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          activeRemotePeer.isCloudOnly
                                              ? 'A distancia · nube'
                                              : 'Red local · instantáneo (${activeRemotePeer.ip})',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Control de volumen remoto en tiempo real (como Spotify Connect)
                      if (!isLocalActive) ...[
                        const SizedBox(height: 12),
                        _RemoteVolumeSlider(
                          volume: remoteVolume,
                          accent: _spotifyGreen,
                          onChanged: (val) {
                            unawaited(
                              ref
                                  .read(playerControllerProvider.notifier)
                                  .setVolume(val),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // 2. Otros dispositivos disponibles (un toque para transferir)
              if (!isLocalActive || otherPeers.isNotEmpty) ...[
                Text(
                  'Seleccionar un dispositivo',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),

                // Fila "Este teléfono / Esta PC" cuando otro equipo está sonando
                if (!isLocalActive && authService.isAuthenticated)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DeviceTargetTile(
                      icon: _getPlatformIcon(defaultTargetPlatform.name),
                      title: thisDeviceLabel,
                      subtitle: 'Transferir reproducción aquí',
                      dotColor: colors.primary,
                      trailingLabel: 'Transferir aquí',
                      cardSurface: cardSurface,
                      cardBorder: cardBorder,
                      onTap: transferToThisDevice,
                    ),
                  ),

                // Resto de dispositivos de la cuenta (LAN primero, luego nube)
                for (final peer in otherPeers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DeviceTargetTile(
                      icon: _getPlatformIcon(peer.platform),
                      title: peer.deviceName,
                      subtitle: peer.isCloudOnly
                          ? 'En línea · a distancia (nube)'
                          : 'Red local · instantáneo (${peer.ip})',
                      dotColor: peer.isCloudOnly
                          ? colors.primary
                          : _spotifyGreen,
                      trailingLabel: hasSession ? 'Reproducir' : 'Conectar',
                      cardSurface: cardSurface,
                      cardBorder: cardBorder,
                      onTap: () => transferToPeer(peer),
                    ),
                  ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Buscando tus dispositivos...',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Abre Inutix Music en cualquier equipo con tu misma cuenta: se vinculan solos, estén en la misma red o a distancia.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Opción de móvil: enviar siempre a la PC cuando esté encendida
              if (isMobilePlatform && targets.any((p) => p.isHost)) ...[
                const SizedBox(height: 4),
                SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  dense: true,
                  title: Text(
                    'Reproducir siempre en la PC',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Envía canciones a tu PC automáticamente al dar play',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  value: syncService.autoPlayOnPc,
                  onChanged: (val) => syncService.setAutoPlayOnPc(val),
                ),
              ],

              // Listening Rooms (Salas sincronizadas con amigos)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Builder(
                  builder: (context) {
                    final room =
                        ref.watch(listeningRoomStateProvider).asData?.value ??
                        ref.watch(listeningRoomServiceProvider).room;
                    return _DeviceTargetTile(
                      icon: Icons.groups_rounded,
                      title: room != null
                          ? 'Sala en vivo · ${room.name}'
                          : 'Listening Rooms (Salas con amigos)',
                      subtitle: room != null
                          ? 'Código ${room.code} · ${room.activeMembersAt(DateTime.now()).length} escuchando'
                          : 'Crea o únete a una sala sincronizada con cola y reacciones',
                      dotColor: room != null
                          ? _spotifyGreen
                          : colors.primary,
                      trailingLabel: room != null ? 'Abrir' : 'Entrar',
                      cardSurface: cardSurface,
                      cardBorder: cardBorder,
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(ListeningRoomSheet.show(context));
                      },
                    );
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.router_rounded,
                      size: 15,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        authService.isAuthenticated
                            ? 'Este dispositivo: ${authService.deviceName} · '
                                  '${syncService.localAddressHint}:${syncService.currentLanPort}'
                            : 'Inicia la misma cuenta en ambos equipos para vincularlos automáticamente.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
      case 'ios':
        return Icons.phone_android_rounded;
      case 'linux':
      case 'macos':
        return Icons.laptop_rounded;
      case 'windows':
        return Icons.desktop_windows_rounded;
      default:
        return Icons.speaker_rounded;
    }
  }
}

class _DeviceTargetTile extends StatelessWidget {
  const _DeviceTargetTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.dotColor,
    required this.trailingLabel,
    required this.cardSurface,
    required this.cardBorder,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color dotColor;
  final String trailingLabel;
  final Color cardSurface;
  final Color cardBorder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: colors.onSurface, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  trailingLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteVolumeSlider extends StatefulWidget {
  const _RemoteVolumeSlider({
    required this.volume,
    required this.accent,
    required this.onChanged,
  });

  final double volume;
  final Color accent;
  final ValueChanged<double> onChanged;

  @override
  State<_RemoteVolumeSlider> createState() => _RemoteVolumeSliderState();
}

class _RemoteVolumeSliderState extends State<_RemoteVolumeSlider> {
  double? _draggingValue;

  @override
  Widget build(BuildContext context) {
    final value = (_draggingValue ?? widget.volume).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final icon = value <= 0.01
        ? Icons.volume_off_rounded
        : value < 0.5
        ? Icons.volume_down_rounded
        : Icons.volume_up_rounded;

    return Row(
      children: [
        Icon(icon, size: 20, color: widget.accent),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: widget.accent,
              thumbColor: widget.accent,
              inactiveTrackColor: colors.onSurface.withValues(alpha: 0.16),
            ),
            child: Slider(
              value: value,
              onChanged: (next) {
                setState(() => _draggingValue = next);
              },
              onChangeEnd: (next) {
                setState(() => _draggingValue = null);
                widget.onChanged(next);
              },
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${(value * 100).round()}%',
            maxLines: 1,
            textAlign: TextAlign.end,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
