import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_ui.dart';

import '../../../../services/audio_output/audio_output_service.dart';
import '../../../../services/casting/cast_coordinator.dart';
import '../../../../services/player/cast_aware_player_service.dart';
import '../../../../services/player/player_audio_output.dart';
import '../../../../services/player/player_service.dart';
import '../providers/audio_route_providers.dart';
import '../providers/music_providers.dart';
import 'playback_menu_bottom_sheet.dart';

Future<void> showAudioOutputPicker(BuildContext context, WidgetRef ref) async {
  if (switch (Theme.of(context).platform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS => true,
    _ => false,
  }) {
    await showPlaybackMenuBottomSheet<void>(
      context: context,
      builder: (_) => const DesktopAudioOutputMenu(),
    );
    return;
  }
  try {
    final player = ref.read(playerServiceProvider);
    if (player is CastAwarePlayerService && player.isCasting) {
      await player.disconnectCast();
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _MobileAudioOutputSheet(),
    );
  } catch (_) {
    if (context.mounted) _showOutputUnavailable(context, ref);
  }
}

class _MobileAudioOutputSheet extends ConsumerStatefulWidget {
  const _MobileAudioOutputSheet();

  @override
  ConsumerState<_MobileAudioOutputSheet> createState() =>
      _MobileAudioOutputSheetState();
}

class _MobileAudioOutputSheetState
    extends ConsumerState<_MobileAudioOutputSheet> {
  AudioOutputState _state = const AudioOutputState();
  StreamSubscription<AudioOutputState>? _sub;
  bool _loading = true;
  bool _busy = false;
  double? _dragVolume;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final service = ref.read(audioOutputServiceProvider);
    _sub = service.changes.listen((next) {
      if (mounted) setState(() => _state = next);
    });
    final initial = await service.startWatching();
    if (mounted) {
      setState(() {
        _state = initial;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(ref.read(audioOutputServiceProvider).stopWatching());
    super.dispose();
  }

  IconData _routeIcon(AudioOutputType type) => switch (type) {
    AudioOutputType.bluetooth => Icons.headphones_rounded,
    AudioOutputType.wired => Icons.headset_rounded,
    AudioOutputType.usb => Icons.usb_rounded,
    AudioOutputType.speaker => Icons.phone_android_rounded,
    AudioOutputType.other => Icons.speaker_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final service = ref.read(audioOutputServiceProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset + 18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: colors.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.speaker_rounded, color: colors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Salida de audio',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 20),
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
            )
          else if (_state.routes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No se detectaron salidas de audio adicionales.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final route in _state.routes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: route.selected
                      ? colors.primary.withValues(alpha: 0.14)
                      : colors.surfaceContainerLow.withValues(alpha: 0.9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: route.selected
                          ? colors.primary.withValues(alpha: 0.5)
                          : colors.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _busy || !route.selectable
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            try {
                              await service.selectRoute(route.id);
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _routeIcon(route.type),
                            color: route.selected
                                ? colors.primary
                                : colors.onSurfaceVariant,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              route.name.isEmpty ? 'Este dispositivo' : route.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: route.selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: route.selected
                                    ? colors.primary
                                    : colors.onSurface,
                              ),
                            ),
                          ),
                          if (route.selected)
                            Icon(
                              Icons.check_circle_rounded,
                              color: colors.primary,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          if (!_loading && _state.volumeAdjustable) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.volume_down_rounded,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                Expanded(
                  child: Slider(
                    value: (_dragVolume ?? _state.volume).clamp(0.0, 1.0),
                    onChanged: (v) => setState(() => _dragVolume = v),
                    onChangeEnd: (v) async {
                      await service.setVolume(v);
                      if (mounted) setState(() => _dragVolume = null);
                    },
                  ),
                ),
                Icon(
                  Icons.volume_up_rounded,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ],
          if (_state.hasSystemPicker) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await service.showSystemPicker();
              },
              icon: const Icon(Icons.tune_rounded, size: 17),
              label: const Text('Selector avanzado del sistema'),
            ),
          ],
        ],
      ),
    );
  }
}

void _showOutputUnavailable(BuildContext context, WidgetRef ref) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(ref.read(appStringsProvider).outputUnavailable)),
  );
}

Future<void> showCastDevicesMenu(BuildContext context) =>
    showPlaybackMenuBottomSheet<void>(
      context: context,
      builder: (_) => const CastDevicesMenu(),
    );

class DesktopAudioOutputMenu extends ConsumerStatefulWidget {
  const DesktopAudioOutputMenu({super.key});

  @override
  ConsumerState<DesktopAudioOutputMenu> createState() =>
      _DesktopAudioOutputMenuState();
}

class _DesktopAudioOutputMenuState
    extends ConsumerState<DesktopAudioOutputMenu> {
  bool _busy = false;
  String? _message;
  double? _dragVolume;

  Future<void> _select(PlayerAudioOutput output, String id) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await output.selectAudioOutput(id);
    } catch (_) {
      if (mounted) {
        _message = ref.read(appStringsProvider).playerAudioControlFailed;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final player = ref.watch(playerServiceProvider);
    final output = player is PlayerAudioOutput
        ? player as PlayerAudioOutput
        : null;
    return StreamBuilder<PlayerAudioOutputState>(
      stream: output?.audioOutputStream,
      initialData: output?.audioOutputState ?? const PlayerAudioOutputState(),
      builder: (context, snapshot) {
        final state = snapshot.data ?? const PlayerAudioOutputState();
        final devices = {
          systemDefaultAudioDeviceId: strings.systemDefaultAudioOutput,
          for (final device in state.devices)
            if (device.id != systemDefaultAudioDeviceId)
              device.id: device.name.isEmpty ? device.id : device.name,
        };
        return _RouteMenuLayout(
          menuKey: 'desktop-audio-output-menu',
          title: strings.playerAudioOutput,
          children: [
            Text(strings.playerAudioOutputHint),
            const SizedBox(height: 12),
            if (!state.supported || snapshot.hasError)
              Text(strings.outputLoadFailed),
            if (state.supported)
              for (final device in devices.entries)
                ListTile(
                  key: ValueKey('desktop-audio-output-route-${device.key}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    device.key == systemDefaultAudioDeviceId
                        ? Icons.computer_rounded
                        : Icons.speaker_rounded,
                  ),
                  title: Text(device.value),
                  trailing: state.selectedDeviceId == device.key
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  enabled: !_busy && !snapshot.hasError,
                  onTap: output == null
                      ? null
                      : () => _select(output, device.key),
                ),
            const Divider(height: 24),
            Text(
              strings.playerVolume,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            StreamBuilder<PlayerSnapshot>(
              stream: player.snapshotStream,
              initialData: player.currentSnapshot,
              builder: (context, snapshot) => Row(
                children: [
                  const Icon(
                    Icons.volume_down_rounded,
                    size: 24 * appVolumeIconScale,
                  ),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('desktop-audio-output-volume'),
                      value: (_dragVolume ?? snapshot.data!.volume).clamp(0, 1),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _dragVolume = value),
                      onChangeEnd: _busy
                          ? null
                          : (value) async {
                              try {
                                await player.setVolume(value);
                              } catch (_) {
                                if (mounted) {
                                  _message = strings.playerAudioControlFailed;
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _dragVolume = null);
                                }
                              }
                            },
                    ),
                  ),
                  const Icon(
                    Icons.volume_up_rounded,
                    size: 24 * appVolumeIconScale,
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null) Text(_message!),
          ],
        );
      },
    );
  }
}

class AudioOutputMenu extends ConsumerStatefulWidget {
  const AudioOutputMenu({super.key});
  @override
  ConsumerState<AudioOutputMenu> createState() => _AudioOutputMenuState();
}

class _AudioOutputMenuState extends ConsumerState<AudioOutputMenu> {
  bool _busy = false;
  String? _message;
  double? _dragVolume;

  Future<void> _select(AudioOutputRoute route) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final strings = ref.read(appStringsProvider);
    try {
      final player = ref.read(playerServiceProvider);
      if (player is CastAwarePlayerService && player.isCasting) {
        await player.disconnectCast();
      }
      final selected = await ref
          .read(audioOutputServiceProvider)
          .selectRoute(route.id);
      if (!selected && mounted) _message = strings.outputUnavailable;
    } catch (_) {
      if (mounted) _message = strings.outputUnavailable;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _systemPicker() async {
    try {
      final player = ref.read(playerServiceProvider);
      if (player is CastAwarePlayerService && player.isCasting) {
        await player.disconnectCast();
      }
      if (!mounted) return;
      if (!await ref.read(audioOutputServiceProvider).showSystemPicker() &&
          mounted) {
        setState(
          () => _message = ref.read(appStringsProvider).outputUnavailable,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = ref.read(appStringsProvider).outputUnavailable,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final output = ref.watch(audioOutputStateProvider);
    final cast = ref.watch(castStateProvider).asData?.value;
    return _RouteMenuLayout(
      menuKey: 'audio-output-menu',
      title: strings.audioOutput,
      children: [
        if (cast?.connected == true)
          ListTile(
            leading: const Icon(Icons.cast_connected_rounded),
            title: Text(cast!.device!.name),
            subtitle: Text(strings.castTo),
            trailing: const Icon(Icons.check_rounded),
          ),
        ...output.when(
          loading: () => [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (_, _) => [Text(strings.outputLoadFailed)],
          data: (state) => [
            if (!state.supported) Text(strings.outputLoadFailed),
            for (final route in state.routes)
              ListTile(
                key: ValueKey('audio-output-route-${route.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(_outputIcon(route.type)),
                title: Text(
                  route.type == AudioOutputType.speaker
                      ? strings.thisPhone
                      : route.name,
                ),
                subtitle:
                    !state.selectionConfirmed &&
                        state.requestedRouteId == route.id
                    ? Text(strings.outputRequested)
                    : null,
                trailing:
                    route.selected &&
                        state.selectionConfirmed &&
                        cast?.connected != true
                    ? Icon(
                        Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                enabled: !_busy && route.selectable,
                onTap: () => _select(route),
              ),
            if (state.hasSystemPicker)
              ListTile(
                key: const ValueKey('audio-output-system-picker'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.settings_bluetooth_rounded),
                title: Text(strings.systemOutputPicker),
                onTap: _busy ? null : _systemPicker,
              ),
            const Divider(height: 24),
            _volume(
              strings: strings,
              value:
                  _dragVolume ??
                  (cast?.connected == true ? cast!.volume : state.volume),
              enabled:
                  !_busy &&
                  (cast?.connected == true || state.volumeAdjustable) &&
                  state.supported,
              remote: cast?.connected == true,
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!),
          ),
      ],
    );
  }

  Widget _volume({
    required AppStrings strings,
    required double value,
    required bool enabled,
    required bool remote,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        remote ? strings.deviceVolume : strings.mediaVolume,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      Row(
        children: [
          const Icon(Icons.volume_down_rounded, size: 24 * appVolumeIconScale),
          Expanded(
            child: Slider(
              key: const ValueKey('audio-output-volume'),
              value: value.clamp(0, 1),
              onChanged: enabled
                  ? (value) => setState(() => _dragVolume = value)
                  : null,
              onChangeEnd: enabled
                  ? (value) async {
                      try {
                        if (remote) {
                          await ref
                              .read(castCoordinatorProvider)
                              .setVolume(value);
                        } else {
                          await ref
                              .read(audioOutputServiceProvider)
                              .setVolume(value);
                        }
                      } catch (_) {
                        if (mounted) _message = strings.outputUnavailable;
                      } finally {
                        if (mounted) setState(() => _dragVolume = null);
                      }
                    }
                  : null,
            ),
          ),
          const Icon(Icons.volume_up_rounded, size: 24 * appVolumeIconScale),
        ],
      ),
    ],
  );
}

class CastDevicesMenu extends ConsumerStatefulWidget {
  const CastDevicesMenu({super.key});
  @override
  ConsumerState<CastDevicesMenu> createState() => _CastDevicesMenuState();
}

class _CastDevicesMenuState extends ConsumerState<CastDevicesMenu> {
  bool _busy = false;
  String? _message;
  late CastCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(castCoordinatorProvider);
    unawaited(_coordinator.startDiscovery());
  }

  @override
  void dispose() {
    unawaited(_coordinator.stopDiscovery());
    super.dispose();
  }

  Future<void> _connect(CastDevice device) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final strings = ref.read(appStringsProvider);
    try {
      final player = ref.read(playerServiceProvider);
      if (player is! CastAwarePlayerService) {
        throw UnsupportedError('Cast backend unavailable.');
      }
      await player.connectCast(device);
    } catch (_) {
      if (mounted) _message = strings.castFailed;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final player = ref.read(playerServiceProvider);
      if (player is CastAwarePlayerService) await player.disconnectCast();
    } catch (_) {
      if (mounted) _message = ref.read(appStringsProvider).castFailed;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final state =
        ref.watch(castStateProvider).asData?.value ?? _coordinator.state;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return _RouteMenuLayout(
      menuKey: 'cast-devices-menu',
      title: strings.castTo,
      children: [
        Text(
          strings.castNetworkHint,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        for (final device in state.devices)
          ListTile(
            key: ValueKey('cast-device-${device.protocol.name}-${device.id}'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.speaker_group_rounded),
            title: Text(device.name),
            subtitle: Text(
              device.protocol == CastProtocol.googleCast
                  ? 'Google Cast'
                  : 'DLNA / UPnP',
            ),
            trailing:
                state.device?.id == device.id &&
                    state.device?.protocol == device.protocol
                ? Icon(
                    Icons.check_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            enabled: !_busy,
            onTap: () => _connect(device),
          ),
        if (state.devices.isEmpty && !state.discovering)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(strings.castNoDevices),
          ),
        if (ios)
          ListTile(
            key: const ValueKey('cast-airplay-picker'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.airplay_rounded),
            title: const Text('AirPlay'),
            enabled: !_busy,
            onTap: () async {
              await _disconnect();
              if (!mounted) return;
              try {
                await ref.read(audioOutputServiceProvider).showSystemPicker();
              } catch (_) {
                if (mounted) {
                  setState(() => _message = strings.outputUnavailable);
                }
              }
            },
          ),
        if (state.connected)
          ListTile(
            key: const ValueKey('cast-disconnect'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cast_rounded),
            title: Text(strings.castDisconnect),
            subtitle: Text(state.device!.name),
            enabled: !_busy,
            onTap: _disconnect,
          ),
        if (state.discovering || _busy)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.discovering ? strings.castSearching : strings.castTo,
                  ),
                ),
              ],
            ),
          ),
        if (_message != null) Text(_message!),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const ValueKey('cast-refresh'),
          onPressed: _busy || state.discovering
              ? null
              : () => _coordinator.startDiscovery(),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(strings.castRefresh),
        ),
      ],
    );
  }
}

class _RouteMenuLayout extends StatelessWidget {
  const _RouteMenuLayout({
    required this.menuKey,
    required this.title,
    required this.children,
  });
  final String menuKey;
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      key: ValueKey(menuKey),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                key: ValueKey('$menuKey-close'),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

IconData _outputIcon(AudioOutputType type) => switch (type) {
  AudioOutputType.speaker => Icons.smartphone_rounded,
  AudioOutputType.bluetooth => Icons.bluetooth_audio_rounded,
  AudioOutputType.wired => Icons.headphones_rounded,
  AudioOutputType.usb => Icons.usb_rounded,
  AudioOutputType.other => Icons.speaker_rounded,
};
