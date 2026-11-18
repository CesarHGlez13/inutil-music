import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/firebase/firebase_sync_providers.dart';
import '../../../../core/theme/inutil_icons.dart';
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
        );
      }),
    );
    final remoteSession = syncService.remoteSession;
    final isLocalActive = syncService.isCurrentDeviceActive;
    final autoPairedPeer = syncService.autoPairedPeer;
    final otherPeers = syncService.discoveredPeers
        .where((peer) => peer.deviceId != autoPairedPeer?.deviceId)
        .toList(growable: false);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cardSurface = colors.surfaceContainerLow.withValues(alpha: 0.92);
    final cardBorder = colors.outlineVariant.withValues(alpha: 0.45);

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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.primary.withValues(alpha: 0.22),
                          colors.primary.withValues(alpha: 0.07),
                        ],
                      ),
                    ),
                    child: Center(
                      child: InutilIcon(
                        InutilGlyph.devices,
                        color: colors.primary,
                        size: 21,
                        filled: autoPairedPeer != null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Conectar a un dispositivo',
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
                                      'Misma cuenta · Vinculado automático',
                                      style: theme.textTheme.labelSmall?.copyWith(
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
                                playerTrack.trackId ??
                                remoteSession?.trackId;
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
                                    .pause(),
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.speaker_group_rounded,
                            size: 19,
                          ),
                          label: const Text(
                            'Reproducir en la PC',
                            style: TextStyle(fontWeight: FontWeight.w700),
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
                              'Buscando tu PC en la red local...',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Abre Inútil Music en la PC con tu misma cuenta para vincular al instante.',
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
                  'Otros dispositivos en tu red',
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
                                      '${peer.ip}:${peer.port} · en línea',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.north_east_rounded,
                                size: 17,
                                color: colors.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],

              // Sesión activa y controles remotos
              if (remoteSession != null && remoteSession.trackId.isNotEmpty) ...[
                Text(
                  'Sesión de reproducción actual',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colors.primary.withValues(
                        alpha: isLocalActive ? 0.42 : 0.28,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getPlatformIcon(
                              remoteSession.activeDevicePlatform,
                            ),
                            color: colors.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  remoteSession.title.isNotEmpty
                                      ? remoteSession.title
                                      : 'Canción activa',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Sonando en: ${remoteSession.activeDeviceName}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isLocalActive)
                            FilledButton(
                              onPressed: () {
                                syncService.transferPlaybackToThisDevice(
                                  trackId: remoteSession.trackId,
                                  title: remoteSession.title,
                                  artist: remoteSession.artist,
                                  album: remoteSession.album,
                                  thumbnailUrl: remoteSession.thumbnailUrl,
                                  positionMs: remoteSession.positionMs,
                                  durationMs: remoteSession.durationMs,
                                  isPlaying: remoteSession.isPlaying,
                                );
                              },
                              child: const Text('Transferir aquí'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.onSurface.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous_rounded),
                              color: colors.onSurface,
                              onPressed: () {
                                syncService.sendRemoteControlCommand(
                                  commandType: 'previous',
                                );
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                remoteSession.isPlaying
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_filled_rounded,
                                size: 42,
                              ),
                              color: colors.primary,
                              onPressed: () {
                                syncService.sendRemoteControlCommand(
                                  commandType: remoteSession.isPlaying
                                      ? 'pause'
                                      : 'play',
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded),
                              color: colors.onSurface,
                              onPressed: () {
                                syncService.sendRemoteControlCommand(
                                  commandType: 'next',
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
