import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/inutil_icons.dart';
import '../providers/music_providers.dart';

/// Sleek bottom sheet for managing the playback Sleep Timer directly from the
/// player without leaving the listening flow.
class InutilSleepTimerSheet extends ConsumerWidget {
  const InutilSleepTimerSheet({super.key});

  static const _presets = <({String label, Duration duration})>[
    (label: '15 minutos', duration: Duration(minutes: 15)),
    (label: '30 minutos', duration: Duration(minutes: 30)),
    (label: '45 minutos', duration: Duration(minutes: 45)),
    (label: '1 hora', duration: Duration(hours: 1)),
    (label: '1 hora y 30 min', duration: Duration(minutes: 90)),
  ];

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const InutilSleepTimerSheet(),
    );
  }

  String _formatRemaining(Duration d) {
    final totalSeconds = d.inSeconds.clamp(0, 86400);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(sleepTimerControllerProvider);
    final controller = ref.read(sleepTimerControllerProvider.notifier);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final surface = AppColors.cardSurfaceFor(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset + 18),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.surface.withValues(alpha: 0.92),
          surface,
        ),
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
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.primary.withValues(alpha: 0.24),
                      colors.primary.withValues(alpha: 0.08),
                    ],
                  ),
                ),
                child: Center(
                  child: InutilIcon(
                    InutilGlyph.sleepTimer,
                    size: 22,
                    color: colors.primary,
                    filled: timerState.isActive,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Temporizador de sueño',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timerState.isActive
                          ? 'Se detendrá en ${_formatRemaining(timerState.remaining)}'
                          : 'Detiene la música automáticamente',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: timerState.isActive
                            ? colors.primary
                            : colors.onSurfaceVariant,
                        fontWeight: timerState.isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 20),
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final preset in _presets) ...[
            Builder(
              builder: (context) {
                final selected =
                    timerState.isActive &&
                    timerState.selectedDuration == preset.duration;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: selected
                        ? colors.primary.withValues(alpha: 0.14)
                        : colors.onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        controller.start(preset.duration);
                        Navigator.of(context).pop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                preset.label,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: selected
                                      ? colors.primary
                                      : colors.onSurface,
                                ),
                              ),
                            ),
                            if (selected)
                              Icon(
                                Icons.check_circle_rounded,
                                size: 20,
                                color: colors.primary,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
          if (timerState.isActive) ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                controller.cancel();
                Navigator.of(context).pop();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.error,
                side: BorderSide(color: colors.error.withValues(alpha: 0.45)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.timer_off_outlined, size: 19),
              label: const Text(
                'Desactivar temporizador',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
