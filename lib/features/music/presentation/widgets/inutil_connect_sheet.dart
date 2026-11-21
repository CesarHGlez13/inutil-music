import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/firebase/firebase_sync_providers.dart';
import '../../domain/entities/track_info.dart';
import '../providers/music_providers.dart';

/// Modal estilo Spotify Connect para control de reproducción y cambio de dispositivos.
/// Detecta y conecta automáticamente con la PC si la cuenta de usuario es la misma.
class InutilConnectSheet extends ConsumerWidget {
  const InutilConnectSheet({super.key});

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
    // Select only static track metadata so 200 ms playback position ticks
    // never rebuild the Connect bottom sheet and peer cards.
    final playerTrack = ref.watch(
      playerControllerProvider.select((player) {
        final snapshot = player.value;
        return (
          trackId: snapshot?.trackId,
          title: snapshot?.title,
          artist: snapshot?.artist,
          album: snapshot?.album,
          thumbnailUrl: snapshot?.thumbnailUrl,
          positionMs: snapshot?.position.inMilliseconds,
        );
      }),
    );
    final remoteSession = syncService.remoteSession;
    final isLocalActive = syncService.isCurrentDeviceActive;
    final autoPairedPeer = syncService.autoPairedPeer;
    // Destinos de la cuenta: los de la red local y los que están en línea a
    // través de Firestore. Así la lista funciona aunque el PC esté en otra red
    // o el firewall bloquee los puertos, igual que Spotify Connect.
    final otherPeers = syncService.connectTargets
        .where((peer) => peer.deviceId != autoPairedPeer?.deviceId)
        .toList(growable: false);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cardSurface = colors.surfaceContainerLow.withValues(alpha: 0.92);
    final cardBorder = colors.outlineVariant.withValues(alpha: 0.45);

    // Nombre del equipo actual, como hace Spotify ("Este telefono" en el
    // movil, "Esta PC"/"Este ordenador" en escritorio).
    final thisDeviceLabel = switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => 'Este teléfono',
      TargetPlatform.windows => 'Esta PC',
      _ => 'Este ordenador',
    };
    // Metadatos de la sesion visible: manda la sesion de la nube y en su
    // defecto lo que tiene el reproductor local.
    final sessionTitle =
        (remoteSession != null && remoteSession.title.isNotEmpty)
        ? remoteSession.title
        : playerTrack.title ?? '';
    final sessionArtist =
        (remoteSession != null && remoteSession.artist.isNotEmpty)
        ? remoteSession.artist
        : playerTrack.artist ?? '';
    final hasSession = sessionTitle.isNotEmpty;
    final sessionLine = hasSession
        ? (sessionArtist.isEmpty
              ? sessionTitle
              : '$sessionTitle — $sessionArtist')
        : null;
    final sessionBadge = !hasSession
        ? null
        : ((remoteSession?.isPlaying ?? false) ? 'Reproduciendo' : 'En pausa');
    // Rastros de la sesion activa para poder reproducir en otro equipo desde
    // su propio menu, sin necesitar el mini reproductor embebido.
    final sessionTrackId =
        (remoteSession != null && remoteSession.trackId.isNotEmpty)
        ? remoteSession.trackId
        : playerTrack.trackId;
    final sessionPositionMs =
        remoteSession?.positionMs ?? playerTrack.positionMs ?? 0;

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
              const SizedBox(height: 18),

              // Equipo actual, como la fila destacada de Spotify Connect:
              // nombre, estado, cancion activa en color primario y su glifo.
              // Se quito de aqui el mini reproductor con botones de transporte
              // (previo/play/siguiente): la app ya tiene su propio reproductor
              // y su mini player, y repetirlo dentro de la hoja confundia.
              if (authService.isAuthenticated)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.45),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        thisDeviceLabel,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
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
                                          color: colors.onSurface.withValues(
                                            alpha: 0.10,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          sessionBadge,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
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
                                        : colors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            _getPlatformIcon(defaultTargetPlatform.name),
                            color: colors.primary,
                            size: 30,
                          ),
                        ],
                      ),
                      if (remoteSession != null &&
                          hasSession &&
                          !isLocalActive) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () async {
                              final nav = Navigator.maybeOf(context);
                              final track = TrackInfo(
                                id: remoteSession.trackId,
                                title: remoteSession.title.isNotEmpty
                                    ? remoteSession.title
                                    : 'Canción activa',
                                artist: remoteSession.artist.isNotEmpty
                                    ? remoteSession.artist
                                    : 'Inútil Music',
                                album: remoteSession.album,
                                thumbnailUrl: remoteSession.thumbnailUrl,
                                url: remoteSession.trackId,
                                duration: remoteSession.durationMs > 0
                                    ? Duration(
                                        milliseconds: remoteSession.durationMs,
                                      )
                                    : null,
                              );
                              await syncService.transferPlaybackToThisDevice(
                                trackId: remoteSession.trackId,
                                title: remoteSession.title,
                                artist: remoteSession.artist,
                                album: remoteSession.album,
                                thumbnailUrl: remoteSession.thumbnailUrl,
                                positionMs: remoteSession.positionMs,
                                durationMs: remoteSession.durationMs,
                                isPlaying: remoteSession.isPlaying,
                              );
                              await ref
                                  .read(playerControllerProvider.notifier)
                                  .playRemote(track);
                              if (remoteSession.positionMs > 0) {
                                await ref
                                    .read(playerControllerProvider.notifier)
                                    .seek(
                                      Duration(
                                        milliseconds: remoteSession.positionMs,
                                      ),
                                    );
                              }
                              nav?.pop();
                            },
                            child: const Text('Transferir aquí'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // Vinculación automática por misma cuenta
              if (autoPairedPeer != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.45),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getPlatformIcon(autoPairedPeer.platform),
                            color: colors.primary,
                            size: 30,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  autoPairedPeer.deviceName,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: colors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      autoPairedPeer.isCloudOnly
                                          ? 'Misma cuenta · Vinculado por la nube'
                                          : 'Misma cuenta · Vinculado automático',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: colors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final trackId =
                                playerTrack.trackId ?? remoteSession?.trackId;
                            final title =
                                playerTrack.title ??
                                remoteSession?.title ??
                                'Canción';
                            final artist =
                                playerTrack.artist ??
                                remoteSession?.artist ??
                                'Inútil Music';
                            final album =
                                playerTrack.album ?? remoteSession?.album;
                            final thumb =
                                playerTrack.thumbnailUrl ??
                                remoteSession?.thumbnailUrl;
                            final pos =
                                ref
                                    .read(playerControllerProvider)
                                    .value
                                    ?.position
                                    .inMilliseconds ??
                                0;

                            if (trackId != null && trackId.isNotEmpty) {
                              final nav = Navigator.maybeOf(context);
                              unawaited(syncService.setAutoPlayOnPc(true));
                              await syncService.playTrackOnPeer(
                                trackId: trackId,
                                title: title,
                                artist: artist,
                                album: album,
                                thumbnailUrl: thumb,
                                positionMs: pos,
                              );
                              unawaited(
                                ref
                                    .read(playerControllerProvider.notifier)
                                    .pause(notifyPeer: false),
                              );
                              nav?.pop();
                            }
                          },
                          icon: const Icon(
                            Icons.speaker_group_rounded,
                            size: 19,
                          ),
                          label: Text(
                            'Reproducir en ${autoPairedPeer.deviceName}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          'Reproducir siempre en la PC',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          'Envía canciones a la PC automáticamente al dar play',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        value: syncService.autoPlayOnPc,
                        onChanged: (val) => syncService.setAutoPlayOnPc(val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
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
                              'Abre Inútil Music en cualquier equipo con tu misma cuenta: se vinculan solos, estén en la misma red o a distancia.',
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
                const SizedBox(height: 18),
              ],

              // Otros dispositivos en tu red
              if (otherPeers.isNotEmpty) ...[
                Text(
                  'En otras redes',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final peer in otherPeers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: cardSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: cardBorder),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => syncService.selectPeer(peer),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _getPlatformIcon(peer.platform),
                                color: colors.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      peer.deviceName,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      peer.isCloudOnly
                                          ? 'En línea · a distancia (por la nube)'
                                          : '${peer.ip}:${peer.port} · en línea · red local',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Opciones para ${peer.deviceName}',
                                color: colors.surfaceContainerHigh,
                                icon: Icon(
                                  Icons.more_horiz_rounded,
                                  size: 19,
                                  color: colors.onSurfaceVariant,
                                ),
                                onSelected: (value) {
                                  if (value == 'play' &&
                                      sessionTrackId != null) {
                                    unawaited(
                                      syncService.playTrackOnPeer(
                                        trackId: sessionTrackId,
                                        title: sessionArtist.isEmpty
                                            ? 'Canción'
                                            : sessionTitle,
                                        artist: sessionArtist.isEmpty
                                            ? 'Inútil Music'
                                            : sessionArtist,
                                        album:
                                            playerTrack.album ??
                                            remoteSession?.album,
                                        thumbnailUrl:
                                            playerTrack.thumbnailUrl ??
                                            remoteSession?.thumbnailUrl,
                                        positionMs: sessionPositionMs,
                                        targetPeer: peer,
                                      ),
                                    );
                                  } else {
                                    syncService.selectPeer(peer);
                                  }
                                },
                                itemBuilder: (menuContext) => [
                                  if (sessionTrackId != null)
                                    const PopupMenuItem(
                                      value: 'play',
                                      child: Text('Reproducir aquí'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'connect',
                                    child: Text('Conectar a este dispositivo'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],

              Padding(
                padding: const EdgeInsets.only(top: 14),
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
        return Icons.phone_android_rounded;
      case 'linux':
        return Icons.computer_rounded;
      case 'windows':
        return Icons.desktop_windows_rounded;
      default:
        return Icons.speaker_rounded;
    }
  }
}
