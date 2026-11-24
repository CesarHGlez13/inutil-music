import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_ui.dart';
import '../../../../services/recommendations/algorithm_control_settings.dart';
import '../providers/music_providers.dart';

/// Full-featured "Centro de control del algoritmo" screen/body that can be
/// rendered inside [SettingsPanel] or opened as a modal sheet from Home.
class AlgorithmControlSettingsView extends ConsumerWidget {
  const AlgorithmControlSettingsView({
    this.bottomPadding = 24,
    super.key,
  });

  final double bottomPadding;

  static Future<void> showSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final spanish =
            Localizations.maybeLocaleOf(context)?.languageCode != 'en';
        return DraggableScrollableSheet(
          initialChildSize: 0.88,
          minChildSize: 0.55,
          maxChildSize: 0.96,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onSurfaceVariant.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                    child: Row(
                      children: [
                        Icon(Icons.tune_rounded, color: colors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            spanish
                                ? 'Centro de control del algoritmo'
                                : 'Algorithm control center',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      child: const AlgorithmControlSettingsView(
                        bottomPadding: 0,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    final settings = settingsAsync.asData?.value;
    final control =
        settings?.algorithmControl ?? AlgorithmControlSettings.defaults;
    final controller = ref.read(settingsControllerProvider.notifier);
    final strings = ref.watch(appStringsProvider);
    final spanish = strings.language != 'en';
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final activePreset = control.activePreset;

    Future<void> updateControl(AlgorithmControlSettings next) async {
      await controller.setAlgorithmControl(next);
    }

    const knownColor = Color(0xFF4F8CFF);
    const discoveryColor = Color(0xFF1ED760);
    const forgottenColor = Color(0xFFFFA94D);
    const wildcardColor = Color(0xFFCC5DE8);

    final cardDecoration = BoxDecoration(
      color: colors.surfaceContainerLow.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(appCardRadius),
      border: Border.all(
        color: colors.outlineVariant.withValues(alpha: 0.35),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Presets rápidos
          Container(
            decoration: cardDecoration,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spanish ? 'Perfiles rápidos' : 'Quick presets',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  spanish
                      ? 'Decide cómo equilibra Inutix Music tus canciones conocidas, descubrimientos y nostalgia.'
                      : 'Choose how Inutix Music balances familiar tracks, discovery, and nostalgia.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in const [
                      AlgorithmPreset.balanced,
                      AlgorithmPreset.discovery,
                      AlgorithmPreset.nostalgia,
                      AlgorithmPreset.noAlgorithm,
                    ])
                      ChoiceChip(
                        key: ValueKey('algorithm-preset-${preset.name}'),
                        selected: activePreset == preset,
                        label: Text(preset.label(spanish: spanish)),
                        onSelected: (_) => controller.applyAlgorithmPreset(preset),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 2. Modo sin algoritmo
          Container(
            decoration: cardDecoration,
            child: SwitchListTile.adaptive(
              key: const ValueKey('algorithm-disabled-switch'),
              secondary: Icon(
                control.algorithmDisabled
                    ? Icons.do_not_disturb_on_rounded
                    : Icons.auto_awesome_rounded,
                color: control.algorithmDisabled
                    ? colors.primary
                    : colors.onSurfaceVariant,
              ),
              title: Text(
                spanish ? 'Modo sin algoritmo' : 'No-algorithm mode',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                spanish
                    ? 'Oculta recomendaciones automáticas en Inicio y desactiva la radio automática al terminar tu cola. Solo suena lo que elijas.'
                    : 'Hides automatic Home recommendations and disables auto-radio when your queue ends. Only what you pick plays.',
              ),
              value: control.algorithmDisabled,
              onChanged: (value) =>
                  updateControl(control.copyWith(algorithmDisabled: value)),
            ),
          ),

          const SizedBox(height: 12),

          // 3. Mezcla personalizada (4 sliders auto-equilibrados a 100%)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: control.algorithmDisabled ? 0.45 : 1.0,
            child: IgnorePointer(
              ignoring: control.algorithmDisabled,
              child: Container(
                decoration: cardDecoration,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            spanish
                                ? 'Mezcla del algoritmo'
                                : 'Algorithm mix',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!control.isDefault)
                          TextButton(
                            onPressed: () =>
                                updateControl(AlgorithmControlSettings.defaults),
                            child: Text(spanish ? 'Restablecer' : 'Reset'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        height: 10,
                        child: Row(
                          children: [
                            if (control.knownPercent > 0)
                              Expanded(
                                flex: control.knownPercent,
                                child: const ColoredBox(color: knownColor),
                              ),
                            if (control.discoveryPercent > 0)
                              Expanded(
                                flex: control.discoveryPercent,
                                child: const ColoredBox(color: discoveryColor),
                              ),
                            if (control.forgottenPercent > 0)
                              Expanded(
                                flex: control.forgottenPercent,
                                child: const ColoredBox(color: forgottenColor),
                              ),
                            if (control.wildcardPercent > 0)
                              Expanded(
                                flex: control.wildcardPercent,
                                child: const ColoredBox(color: wildcardColor),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _WeightSliderRow(
                      key: const ValueKey('algorithm-weight-known'),
                      label: spanish ? 'Conocidas' : 'Familiar',
                      subtitle: spanish
                          ? 'Tus artistas y temas frecuentes'
                          : 'Your frequent tracks & artists',
                      value: control.knownPercent,
                      color: knownColor,
                      onChanged: (v) => updateControl(
                        control.withWeightAdjusted(
                          AlgorithmWeightSlot.known,
                          v,
                        ),
                      ),
                    ),
                    _WeightSliderRow(
                      key: const ValueKey('algorithm-weight-discovery'),
                      label: spanish ? 'Descubrimiento' : 'Discovery',
                      subtitle: spanish
                          ? 'Canciones nuevas afines a tu gusto'
                          : 'Fresh songs matching your taste',
                      value: control.discoveryPercent,
                      color: discoveryColor,
                      onChanged: (v) => updateControl(
                        control.withWeightAdjusted(
                          AlgorithmWeightSlot.discovery,
                          v,
                        ),
                      ),
                    ),
                    _WeightSliderRow(
                      key: const ValueKey('algorithm-weight-forgotten'),
                      label: spanish
                          ? 'Olvidadas (Nostalgia)'
                          : 'Forgotten (Nostalgia)',
                      subtitle: spanish
                          ? 'Activa la fila Modo Nostalgia al subir ≥ 20%'
                          : 'Enables Nostalgia Mode shelf at ≥ 20%',
                      value: control.forgottenPercent,
                      color: forgottenColor,
                      onChanged: (v) => updateControl(
                        control.withWeightAdjusted(
                          AlgorithmWeightSlot.forgotten,
                          v,
                        ),
                      ),
                    ),
                    _WeightSliderRow(
                      key: const ValueKey('algorithm-weight-wildcard'),
                      label: spanish ? 'Sorpresa' : 'Wildcard',
                      subtitle: spanish
                          ? 'Mayor variedad de artistas y hallazgos raros'
                          : 'Wider artist diversity & deeper cuts',
                      value: control.wildcardPercent,
                      color: wildcardColor,
                      onChanged: (v) => updateControl(
                        control.withWeightAdjusted(
                          AlgorithmWeightSlot.wildcard,
                          v,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 4. Anti-repetición
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: control.algorithmDisabled ? 0.45 : 1.0,
            child: IgnorePointer(
              ignoring: control.algorithmDisabled,
              child: Container(
                decoration: cardDecoration,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.repeat_one_on_rounded,
                          size: 20,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          spanish ? 'Anti-repetición' : 'Anti-repetition',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      spanish
                          ? 'Evita recomendarte canciones que ya escuchaste recientemente (sin bloquear nunca tus reproducciones manuales).'
                          : 'Avoids recommending tracks you played recently (never blocks manual playback).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final days in supportedAntiRepetitionDays)
                          ChoiceChip(
                            key: ValueKey('algorithm-antirepeat-$days'),
                            selected: control.antiRepetitionDays == days,
                            label: Text(
                              days == 0
                                  ? (spanish ? 'Desactivado' : 'Off')
                                  : (spanish
                                        ? '$days ${days == 1 ? 'día' : 'días'}'
                                        : '$days ${days == 1 ? 'day' : 'days'}'),
                            ),
                            onSelected: (_) => updateControl(
                              control.copyWith(antiRepetitionDays: days),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 5. Reglas inteligentes
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: control.algorithmDisabled ? 0.45 : 1.0,
            child: IgnorePointer(
              ignoring: control.algorithmDisabled,
              child: Container(
                decoration: cardDecoration,
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      key: const ValueKey('algorithm-penalize-skipped'),
                      title: Text(
                        spanish
                            ? 'Penalizar canciones omitidas'
                            : 'Penalize skipped tracks',
                      ),
                      subtitle: Text(
                        spanish
                            ? 'Reduce el peso de canciones que saltas antes de terminar.'
                            : 'Demotes songs you repeatedly skip early.',
                      ),
                      value: control.penalizeSkippedTracks,
                      onChanged: (value) => updateControl(
                        control.copyWith(penalizeSkippedTracks: value),
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: colors.outlineVariant.withValues(alpha: 0.25),
                    ),
                    SwitchListTile.adaptive(
                      key: const ValueKey('algorithm-prioritize-favorites'),
                      title: Text(
                        spanish
                            ? 'Priorizar favoritos'
                            : 'Prioritize favorites',
                      ),
                      subtitle: Text(
                        spanish
                            ? 'Usa tus favoritos como semillas principales del algoritmo.'
                            : 'Uses your favorites as primary taste seeds.',
                      ),
                      value: control.prioritizeFavorites,
                      onChanged: (value) => updateControl(
                        control.copyWith(prioritizeFavorites: value),
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: colors.outlineVariant.withValues(alpha: 0.25),
                    ),
                    SwitchListTile.adaptive(
                      key: const ValueKey('algorithm-avoid-same-artist'),
                      title: Text(
                        spanish
                            ? 'Evitar mismo artista seguido'
                            : 'Avoid same artist back-to-back',
                      ),
                      subtitle: Text(
                        spanish
                            ? 'Alterna artistas consecutivos en tus listas recomendadas.'
                            : 'Spreads consecutive tracks by the same artist.',
                      ),
                      value: control.avoidSameArtistBackToBack,
                      onChanged: (value) => updateControl(
                        control.copyWith(avoidSameArtistBackToBack: value),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 6. Privacidad de Echo Memory
          Container(
            decoration: cardDecoration,
            child: SwitchListTile.adaptive(
              key: const ValueKey('echo-memory-banner-switch'),
              secondary: Icon(
                Icons.auto_stories_rounded,
                color: (settings?.echoMemoryBannerEnabled ?? true)
                    ? colors.primary
                    : colors.onSurfaceVariant,
              ),
              title: Text(
                spanish
                    ? 'Mostrar Echo Memory al reproducir'
                    : 'Show Echo Memory on playback',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                spanish
                    ? 'Muestra un aviso discreto en el reproductor cuando suena una canción con recuerdo guardado.'
                    : 'Shows a subtle pill in the player when a song with a saved memory plays.',
              ),
              value: settings?.echoMemoryBannerEnabled ?? true,
              onChanged: controller.setEchoMemoryBannerEnabled,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightSliderRow extends StatelessWidget {
  const _WeightSliderRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String subtitle;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$value%',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.16),
              trackHeight: 4,
            ),
            child: Slider(
              min: 0,
              max: 100,
              divisions: 20,
              value: value.toDouble(),
              onChanged: (next) => onChanged((next / 5).round() * 5),
            ),
          ),
        ],
      ),
    );
  }
}
