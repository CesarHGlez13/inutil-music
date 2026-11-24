import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/music/presentation/providers/music_providers.dart';
import '../../features/music/presentation/widgets/home_loading_content.dart';

/// Lienzo neutro mientras `SettingsController` resuelve sus preferencias.
///
/// `settingsControllerProvider` es un `AsyncNotifier` cuyo `build()` hace I/O
/// real de plataforma (`SharedPreferences`, directorio de descargas,
/// `ImagePicker.retrieveLostData`), así que el primer frame siempre lo
/// encuentra en `AsyncLoading` y los fallbacks de `home_page.dart`
/// (`?? defaultPlayerStyle`, artwork `classic`, `spotifyCanvasEnabled ??
/// false`, `appleAnimatedArtworkEnabled ?? false`) pintan el reproductor
/// "Inutix Music clásico" aunque el usuario haya elegido Spotify/Apple o
/// activado el Canvas. Ver ese default y luego el valor guardado es el salto
/// de "primero sale la interfaz vieja y luego la correcta" que se ve a
/// simple vista, y como `player_panel.dart` elige el layout con `KeyedSubtree`
/// de keys distintas el cambio es un remount sin cross-fade: todavía se nota
/// más.
///
/// Pintar un esqueleto uno o dos frames cuesta menos que pintar una interfaz
/// equivocada. El lienzo se retira en cuanto hay `AsyncData` o `AsyncError`
/// —un fallo de preferencias no puede dejar la app bloqueada— o cuando vence
/// `ceiling`, para que un I/O lento nunca se vea como pantalla de carga
/// infinita.
class InutilSettingsHydrationGate extends ConsumerStatefulWidget {
  const InutilSettingsHydrationGate({
    super.key,
    required this.child,
    this.ceiling = const Duration(milliseconds: 1200),
  });

  final Widget child;

  /// Techo tras el cual se pinta el shell con los defaults aunque las
  /// preferencias sigan sin resolver.
  final Duration ceiling;

  @override
  ConsumerState<InutilSettingsHydrationGate> createState() =>
      _InutilSettingsHydrationGateState();
}

class _InutilSettingsHydrationGateState
    extends ConsumerState<InutilSettingsHydrationGate> {
  bool _pastCeiling = false;
  Timer? _ceilingTimer;

  @override
  void initState() {
    super.initState();
    _ceilingTimer = Timer(widget.ceiling, () {
      if (!mounted) return;
      setState(() => _pastCeiling = true);
    });
  }

  @override
  void dispose() {
    _ceilingTimer?.cancel();
    _ceilingTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    if (!_settingsPending(settings) || _pastCeiling) {
      return widget.child;
    }
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: HomeLoadingContent(
            key: const ValueKey('settings-hydration-skeleton'),
            label: 'Cargando Inutix Music',
          ),
        ),
      ),
    );
  }

  /// Sólo `AsyncLoading` cuenta como pendiente: `AsyncError` significa que ya
  /// no hay valores que esperar y el shell debe pintarse igual.
  static bool _settingsPending(AsyncValue<SettingsState> settings) =>
      settings is AsyncLoading<SettingsState>;
}
