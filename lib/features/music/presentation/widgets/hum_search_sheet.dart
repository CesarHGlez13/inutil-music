import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/track_info.dart';
import '../../../../services/youtube_music/search/innertube_audio_search_service.dart';

/// Abre la hoja modal de reconocimiento acústico por voz, canto o tarareo.
Future<TrackInfo?> showHumSearchSheet(
  BuildContext context, {
  InnertubeAudioSearchService? audioService,
}) {
  return showModalBottomSheet<TrackInfo>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black87,
    builder: (ctx) => HumSearchSheet(
      audioService: audioService,
      onTrackSelected: (track) => Navigator.of(ctx).pop(track),
    ),
  );
}

/// Hoja interactiva con ondas neón para búsqueda por tarareo/canto/voz.
class HumSearchSheet extends ConsumerStatefulWidget {
  const HumSearchSheet({
    this.audioService,
    this.initialTracks,
    this.onTrackSelected,
    super.key,
  });

  final InnertubeAudioSearchService? audioService;
  final List<TrackInfo>? initialTracks;
  final ValueChanged<TrackInfo>? onTrackSelected;

  @override
  ConsumerState<HumSearchSheet> createState() => _HumSearchSheetState();
}

class _HumSearchSheetState extends ConsumerState<HumSearchSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;
  late final InnertubeAudioSearchService _service;
  StreamSubscription<double>? _ampSub;

  double _currentAmplitude = 0.4;
  bool _isListening = true;
  bool _isSearching = false;
  String? _errorMessage;
  List<TrackInfo> _results = [];

  @override
  void initState() {
    super.initState();
    _service = widget.audioService ?? InnertubeAudioSearchService();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    if (widget.initialTracks != null && widget.initialTracks!.isNotEmpty) {
      _results = widget.initialTracks!;
      _isListening = false;
    } else {
      _startListeningCycle();
    }
  }

  void _startListeningCycle() {
    _ampSub?.cancel();
    _ampSub = _service.amplitudeStream.listen((amp) {
      if (mounted) {
        setState(() => _currentAmplitude = amp);
      }
    });
    _service.startListening();
  }

  Future<void> _finishListening() async {
    if (!_isListening) return;
    setState(() {
      _isListening = false;
      _isSearching = true;
      _errorMessage = null;
    });
    _ampSub?.cancel();

    try {
      final found = await _service.stopListeningAndSearch();
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _results = found;
        if (found.isEmpty) {
          _errorMessage = 'No encontramos una coincidencia exacta. Intenta de nuevo cantando más claro.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _errorMessage = 'Ocurrió un error al procesar el audio.';
      });
    }
  }

  @override
  void dispose() {
    _ampSub?.cancel();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bgDark = Color(0xFF0A0B10);
    const cyanNeon = Color(0xFF00E5FF);
    const violetNeon = Color(0xFF7C4DFF);

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: bgDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: Color(0x3300E5FF), width: 1.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x4000E5FF),
              blurRadius: 30,
              spreadRadius: -5,
              offset: Offset(0, -6),
            ),
          ],
        ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Handle superior
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Texto de instrucción principal acordado
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Di, canta o tararea un fragmento de la canción',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 8),

            Text(
              _isListening
                  ? 'Escuchando tu voz o melodía...'
                  : _isSearching
                      ? 'Analizando patrón melódico...'
                      : _results.isNotEmpty
                          ? 'Coincidencias encontradas'
                          : 'Listo para escuchar',
              style: TextStyle(
                color: cyanNeon.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),

            // Visualizador de ondas en tiempo real
            if (_isListening || _isSearching)
              SizedBox(
                key: const ValueKey('hum-waveform-visualizer'),
                height: 120,
                width: double.infinity,
                child: AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, _) => CustomPaint(
                    painter: _NeonWaveformPainter(
                      progress: _waveController.value,
                      amplitude: _currentAmplitude,
                      primaryColor: cyanNeon,
                      secondaryColor: violetNeon,
                    ),
                  ),
                ),
              ),

            if (_isListening) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _finishListening,
                icon: const Icon(Icons.search_rounded, color: Colors.black),
                label: const Text(
                  'Buscar canción',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: cyanNeon,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 6,
                  shadowColor: cyanNeon.withValues(alpha: 0.5),
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _results = [];
                    _isListening = true;
                    _errorMessage = null;
                  });
                  _startListeningCycle();
                },
                icon: const Icon(Icons.refresh_rounded, color: cyanNeon),
                label: const Text('Intentar de nuevo', style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: cyanNeon),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ],

            // Lista de resultados
            if (_results.isNotEmpty)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _results.length,
                  separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final track = _results[index];
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty
                              ? Image.network(
                                  track.thumbnailUrl!,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    width: 48,
                                    height: 48,
                                    color: Colors.white10,
                                    child: const Icon(Icons.music_note, color: cyanNeon),
                                  ),
                                )
                              : Container(
                                  width: 48,
                                  height: 48,
                                  color: Colors.white10,
                                  child: const Icon(Icons.music_note, color: cyanNeon),
                                ),
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.play_circle_fill_rounded, color: cyanNeon, size: 36),
                          onPressed: () {
                            widget.onTrackSelected?.call(track);
                          },
                        ),
                        onTap: () {
                          widget.onTrackSelected?.call(track);
                        },
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}
}

/// Pintor de ondas neón reactivas en GPU.
class _NeonWaveformPainter extends CustomPainter {
  const _NeonWaveformPainter({
    required this.progress,
    required this.amplitude,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final double progress;
  final double amplitude;
  final Color primaryColor;
  final Color secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    const barCount = 36;
    final barWidth = size.width / (barCount * 1.8);
    final spacing = (size.width - (barCount * barWidth)) / (barCount - 1);

    for (var i = 0; i < barCount; i++) {
      final x = i * (barWidth + spacing);
      final phase = (progress * 2 * math.pi) + (i * 0.28);
      final wave = (math.sin(phase) + 1.0) / 2.0;
      final dynamicHeight = (12.0 + (wave * amplitude * 80.0)).clamp(8.0, size.height * 0.9);

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + (barWidth / 2), midY),
          width: barWidth,
          height: dynamicHeight,
        ),
        Radius.circular(barWidth / 2),
      );

      final t = i / barCount;
      final color = Color.lerp(primaryColor, secondaryColor, t)!;

      // Brillo neón
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(rect, glowPaint);

      // Barra principal sólida
      final solidPaint = Paint()..color = color;
      canvas.drawRRect(rect, solidPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NeonWaveformPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.amplitude != amplitude;
}
