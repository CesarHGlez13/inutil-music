import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/firebase/firebase_sync_providers.dart';
import '../../../../core/theme/inutil_design_system.dart';
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
    final playerSnapshot = ref.watch(playerControllerProvider).value;
    final remoteSession = syncService.remoteSession;
    final isLocalActive = syncService.isCurrentDeviceActive;
    final autoPairedPeer = syncService.autoPairedPeer;
    // Dispositivos de la misma cuenta que están en la red pero aún no son el
    // destino elegido: el usuario puede pulsarlos para cambiar el mando.
    final otherPeers = syncService.discoveredPeers
        .where((peer) => peer.deviceId != autoPairedPeer?.deviceId)
        .toList(growable: false);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(
                    Icons.devices_rounded,
                    color: colors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Conectar a un dispositivo',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
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
                        color: InutilDesignSystem.primaryNeon.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: InutilDesignSystem.primaryNeon.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        authService.currentUser?.displayName ?? 'César',
                        style: const TextStyle(
                          fontSize: 12,
                          color: InutilDesignSystem.primaryNeon,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // -----------------------------------------------------------------
              // SECCIÓN: VINCULACIÓN AUTOMÁTICA POR MISMA CUENTA
              // -----------------------------------------------------------------
              if (autoPairedPeer != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        InutilDesignSystem.primaryNeon.withValues(alpha: 0.12),
                        InutilDesignSystem.surfaceElevated,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: InutilDesignSystem.primaryNeon.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getPlatformIcon(autoPairedPeer.platform),
                            color: InutilDesignSystem.primaryNeon,
                            size: 32,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  autoPairedPeer.deviceName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: InutilDesignSystem.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: InutilDesignSystem.primaryNeon,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Misma Cuenta · Vinculado Automático',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: InutilDesignSystem.primaryNeon,
                                        fontWeight: FontWeight.w600,
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
                      Row(
                        children: [
                          // Botón para reproducir en la PC
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () async {
                                final trackId = playerSnapshot?.trackId ?? remoteSession?.trackId;
                                final title = playerSnapshot?.title ?? remoteSession?.title ?? 'Canción';
                                final artist = playerSnapshot?.artist ?? remoteSession?.artist ?? 'Inútil Music';
                                final album = playerSnapshot?.album ?? remoteSession?.album;
                                final thumb = playerSnapshot?.thumbnailUrl ?? remoteSession?.thumbnailUrl;
                                final pos = playerSnapshot?.position.inMilliseconds ?? 0;

                                if (trackId != null && trackId.isNotEmpty) {
                                  await syncService.playTrackOnPeer(
                                    trackId: trackId,
                                    title: title,
                                    artist: artist,
                                    album: album,
                                    thumbnailUrl: thumb,
                                    positionMs: pos,
                                  );
                                  // Pausar celular para que solo suene la PC
                                  unawaited(ref.read(playerControllerProvider.notifier).pause());
                                }
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: InutilDesignSystem.primaryNeon,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.speaker_group_rounded, size: 20),
                              label: const Text(
                                'Reproducir en la PC',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Switch para reproducción automática en PC al iniciar
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text(
                          'Reproducir siempre en la PC',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: InutilDesignSystem.textPrimary,
                          ),
                        ),
                        subtitle: const Text(
                          'Envía canciones a la PC automáticamente al darle play en el celular',
                          style: TextStyle(
                            fontSize: 11,
                            color: InutilDesignSystem.textSecondary,
                          ),
                        ),
                        value: syncService.autoPlayOnPc,
                        activeColor: InutilDesignSystem.primaryNeon,
                        onChanged: (val) => syncService.setAutoPlayOnPc(val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: InutilDesignSystem.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: InutilDesignSystem.accentCyan,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Buscando tu PC en la red local...',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: InutilDesignSystem.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Abre Inútil Music en la PC con tu misma cuenta para vincular al instante.',
                              style: TextStyle(
                                fontSize: 12,
                                color: InutilDesignSystem.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // -----------------------------------------------------------------
              // SECCIÓN: OTROS DISPOSITIVOS DE LA MISMA CUENTA EN LA RED
              // -----------------------------------------------------------------
              if (otherPeers.isNotEmpty) ...[
                const Text(
                  'Otros dispositivos en tu red',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: InutilDesignSystem.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                for (final peer in otherPeers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: InutilDesignSystem.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
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
                                color: InutilDesignSystem.textSecondary,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      peer.deviceName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: InutilDesignSystem.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${peer.ip}:${peer.port} · en línea',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: InutilDesignSystem.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.north_east_rounded,
                                size: 16,
                                color: InutilDesignSystem.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
              ],

              // -----------------------------------------------------------------
              // SECCIÓN: SESIÓN ACTIVA Y CONTROLES REMOTOS
              // -----------------------------------------------------------------
              if (remoteSession != null && remoteSession.trackId.isNotEmpty) ...[
                const Text(
                  'Sesión de Reproducción Actual',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: InutilDesignSystem.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: InutilDesignSystem.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isLocalActive
                          ? InutilDesignSystem.primaryNeon.withValues(alpha: 0.4)
                          : InutilDesignSystem.accentCyan.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getPlatformIcon(remoteSession.activeDevicePlatform),
                            color: isLocalActive
                                ? InutilDesignSystem.primaryNeon
                                : InutilDesignSystem.accentCyan,
                            size: 32,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  remoteSession.title.isNotEmpty
                                      ? remoteSession.title
                                      : 'Canción activa',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: InutilDesignSystem.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Sonando en: ${remoteSession.activeDeviceName}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isLocalActive
                                        ? InutilDesignSystem.primaryNeon
                                        : InutilDesignSystem.accentCyan,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isLocalActive)
                            FilledButton.tonal(
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
                              style: FilledButton.styleFrom(
                                backgroundColor: InutilDesignSystem.primaryNeon,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text('Transferir aquí'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Controles remotos en vivo para controlar la PC desde el celular
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous_rounded),
                              color: Colors.white,
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
                              color: InutilDesignSystem.primaryNeon,
                              onPressed: () {
                                syncService.sendRemoteControlCommand(
                                  commandType:
                                      remoteSession.isPlaying ? 'pause' : 'play',
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded),
                              color: Colors.white,
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

              // Pie de diagnóstico: dirección del servidor LAN de este
              // dispositivo, para confirmar que el otro equipo apunta aquí.
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.router_rounded,
                      size: 15,
                      color: InutilDesignSystem.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        authService.isAuthenticated
                            ? 'Este dispositivo: ${authService.deviceName} · '
                                  '${syncService.localAddressHint}:${syncService.currentLanPort}'
                            : 'Inicia la misma cuenta en los dos equipos para '
                                  'vincularlos automáticamente.',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: InutilDesignSystem.textSecondary,
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
