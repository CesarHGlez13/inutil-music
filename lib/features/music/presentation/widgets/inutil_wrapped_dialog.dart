import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/firebase/inutil_promo_popup_service.dart';
import '../../../../core/firebase/inutil_wrapped_service.dart';
import '../../../../core/theme/inutil_icons.dart';
import 'inutil_support_popup.dart';
import 'source_image.dart';

/// Pop-up animado a pantalla completa estilo Spotify Wrapped («Tu Año en
/// Inútil Music»).
///
/// 6 diapositivas interactivas con barra de progreso superior tipo Stories:
/// - Toca a la derecha / izquierda para avanzar o retroceder.
/// - Mantén presionado para pausar la historia.
/// - Botón `✕` superior y gesto atrás siempre activos.
class InutilWrappedDialog extends StatefulWidget {
  const InutilWrappedDialog({
    required this.summary,
    required this.userName,
    this.playlistCount = 0,
    super.key,
  });

  final InutilWrappedSummary summary;
  final String userName;
  final int playlistCount;

  static Future<void> show(
    BuildContext context, {
    required InutilWrappedSummary summary,
    required String userName,
    int playlistCount = 0,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar resumen',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (_, _, _) => InutilWrappedDialog(
        summary: summary,
        userName: userName,
        playlistCount: playlistCount,
      ),
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<InutilWrappedDialog> createState() => _InutilWrappedDialogState();
}

class _InutilWrappedDialogState extends State<InutilWrappedDialog>
    with SingleTickerProviderStateMixin {
  static const int _slideCount = 6;
  static const Duration _slideDuration = Duration(milliseconds: 7500);

  late final AnimationController _progress;
  int _index = 0;

  static const List<List<Color>> _slidePalettes = <List<Color>>[
    [Color(0xFF0A1614), Color(0xFF103B30), Color(0xFF07090E)],
    [Color(0xFF180D24), Color(0xFF3A1C5E), Color(0xFF090A10)],
    [Color(0xFF20120B), Color(0xFF5A2A14), Color(0xFF0A090B)],
    [Color(0xFF0B1626), Color(0xFF164366), Color(0xFF080A10)],
    [Color(0xFF220E1D), Color(0xFF5C1D42), Color(0xFF0A090E)],
    [Color(0xFF0C1512), Color(0xFF193C2D), Color(0xFF07090C)],
  ];

  static const List<Color> _slideAccents = <Color>[
    Color(0xFF34D399),
    Color(0xFFC084FC),
    Color(0xFFFB923C),
    Color(0xFF38BDF8),
    Color(0xFFF472B6),
    Color(0xFF1DB954),
  ];

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: _slideDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (_index < _slideCount - 1) {
            _goTo(_index + 1);
          }
        }
      });
    _progress.forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _goTo(int next) {
    final clamped = next.clamp(0, _slideCount - 1);
    HapticFeedback.selectionClick();
    setState(() => _index = clamped);
    _progress
      ..reset()
      ..forward();
  }

  void _onTapUp(TapUpDetails details, double width) {
    if (details.localPosition.dx < width * 0.34) {
      if (_index > 0) {
        _goTo(_index - 1);
      } else {
        _progress
          ..reset()
          ..forward();
      }
    } else if (_index < _slideCount - 1) {
      _goTo(_index + 1);
    }
  }

  Future<void> _shareSummary() async {
    final s = widget.summary;
    final hoursText = s.totalHours >= 1
        ? '${s.totalHours.toStringAsFixed(1)} horas'
        : '${math.max(1, s.totalMinutes)} minutos';
    final topArtist = s.topArtist?.name ?? 'Inútil Music';
    final topSong = s.topTrack != null
        ? '${s.topTrack!.title} — ${s.topTrack!.artist}'
        : 'Mi música favorita';
    final text =
        '🎧 Mi ${AppConstants.appName} Wrapped ${s.year}\n'
        '⏱ Tiempo escuchado: $hoursText\n'
        '⭐ Artista #1: $topArtist\n'
        '🔥 Canción favorita: $topSong\n'
        '✨ Personalidad: ${s.personalityArchetype.emoji} ${s.personalityArchetype.title}\n\n'
        'Escuchado en ${AppConstants.appName}';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _openSupport() async {
    final campaign =
        await InutilPromoPopupService.instance.nextRotatingCampaign();
    if (!mounted) return;
    await InutilSupportPopupDialog.show(context, campaign);
  }

  @override
  Widget build(BuildContext context) {
    final palette = _slidePalettes[_index % _slidePalettes.length];
    final accent = _slideAccents[_index % _slideAccents.length];
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Material(
      key: const ValueKey('inutil-wrapped-dialog'),
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _onTapUp(d, constraints.maxWidth),
            onLongPressStart: (_) => _progress.stop(),
            onLongPressEnd: (_) => _progress.forward(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeInOutCubic,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: palette,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Orbe ambiental animado.
                  Positioned(
                    top: -90,
                    right: -70,
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 650),
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              accent.withValues(alpha: 0.34),
                              accent.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Contenido principal de la diapositiva.
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      topInset + 54,
                      24,
                      bottomInset + 22,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 420),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.05),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey('wrapped-slide-$_index'),
                        child: _buildSlide(_index, accent),
                      ),
                    ),
                  ),

                  // Barra superior de progreso tipo Stories + botón cerrar.
                  Positioned(
                    top: topInset + 10,
                    left: 16,
                    right: 12,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _progress,
                          builder: (_, _) => Row(
                            children: [
                              for (var i = 0; i < _slideCount; i++) ...[
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      minHeight: 3,
                                      value: i < _index
                                          ? 1.0
                                          : i == _index
                                          ? _progress.value
                                          : 0.0,
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.22,
                                      ),
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                    ),
                                  ),
                                ),
                                if (i < _slideCount - 1)
                                  const SizedBox(width: 5),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'INÚTIL WRAPPED ${widget.summary.year}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              key: const ValueKey('inutil-wrapped-close'),
                              tooltip: 'Cerrar',
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSlide(int index, Color accent) {
    final s = widget.summary;
    return switch (index) {
      0 => _buildIntroSlide(accent, s),
      1 => _buildTimeSlide(accent, s),
      2 => _buildTopArtistSlide(accent, s),
      3 => _buildTopSongSlide(accent, s),
      4 => _buildPersonalitySlide(accent, s),
      _ => _buildFinalShareSlide(accent, s),
    };
  }

  Widget _buildIntroSlide(Color accent, InutilWrappedSummary s) {
    final greetingName = widget.userName.trim().isNotEmpty
        ? widget.userName.trim()
        : 'Melómano';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 36),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.22),
              border: Border.all(color: accent.withValues(alpha: 0.6)),
            ),
            alignment: Alignment.center,
            child: const Text('🎧', style: TextStyle(fontSize: 34)),
          ),
          const SizedBox(height: 28),
          Text(
            'Gracias por ponerle\nbanda sonora a tu ${s.year},\n$greetingName.',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              height: 1.12,
              letterSpacing: -0.9,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            s.hasListeningData
                ? 'Cada canción que repetiste, cada viaje con audífonos y cada madrugada quedó guardada en tu historia musical.'
                : 'A partir de hoy cada canción que escuches sumará minutos, artistas favoritos y estadísticas sincronizadas en tu nube.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 16,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 36),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_rounded, color: Colors.white70, size: 18),
                SizedBox(width: 8),
                Text(
                  'Toca a la derecha para descubrir tu año',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlide(Color accent, InutilWrappedSummary s) {
    final vibe = s.listeningScheduleVibe;
    final showHours = s.totalHours >= 1;
    final targetValue = showHours
        ? s.totalHours
        : math.max(1, s.totalMinutes).toDouble();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'TU TIEMPO EN MÚSICA',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: targetValue),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (_, val, _) => Text(
              showHours ? val.toStringAsFixed(1) : val.round().toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 68,
                fontWeight: FontWeight.w900,
                height: 0.98,
                letterSpacing: -2.0,
              ),
            ),
          ),
          Text(
            showHours ? 'horas de música contigo' : 'minutos de música contigo',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Eso equivale a escuchar ${s.equivalentAlbums} álbumes completos seguidos (${s.totalPlays} reproducciones en ${math.max(1, s.activeDaysCount)} días).',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Text(vibe.emoji, style: const TextStyle(fontSize: 34)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vibe.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        vibe.subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.76),
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopArtistSlide(Color accent, InutilWrappedSummary s) {
    final top = s.topArtist;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            'TU ARTISTA #1 DEL AÑO',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 146,
              height: 146,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.4),
                    blurRadius: 36,
                    spreadRadius: 4,
                  ),
                ],
                border: Border.all(color: accent, width: 3),
              ),
              clipBehavior: Clip.antiAlias,
              child: top?.thumbnailUrl != null
                  ? SourceImage(
                      source: top!.thumbnailUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 320,
                      fallback: _fallbackArt(accent),
                    )
                  : _fallbackArt(accent),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              top?.name ?? 'Escucha tus primeros temas',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
              ),
            ),
          ),
          if (top != null) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                '${math.max(1, (top.seconds / 60).round())} min · ${math.max(1, top.plays)} reproducciones',
                style: TextStyle(
                  color: accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (s.topArtists.length > 1) ...[
            const SizedBox(height: 22),
            Text(
              'TU TOP ARTISTAS',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < s.topArtists.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: i == 0 ? accent : Colors.white54,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        s.topArtists[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      '${math.max(1, (s.topArtists[i].seconds / 60).round())} min',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopSongSlide(Color accent, InutilWrappedSummary s) {
    final top = s.topTrack;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            'TU CANCIÓN FAVORITA',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 156,
              height: 156,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.36),
                    blurRadius: 36,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: top?.thumbnailUrl != null
                  ? SourceImage(
                      source: top!.thumbnailUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 320,
                      fallback: _fallbackArt(accent),
                    )
                  : _fallbackArt(accent),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              top?.title ?? 'Tu próxima obsesión te espera',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (top != null) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                '${top.artist} · ${math.max(1, top.plays)} veces en repeat',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (s.topTracks.length > 1) ...[
            const SizedBox(height: 20),
            Text(
              'TUS TOP CANCIONES',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < s.topTracks.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: i == 0 ? accent : Colors.white54,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.topTracks[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                          Text(
                            s.topTracks[i].artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPersonalitySlide(Color accent, InutilWrappedSummary s) {
    final arch = s.personalityArchetype;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'TU PERSONALIDAD MUSICAL',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Text(arch.emoji, style: const TextStyle(fontSize: 54)),
          const SizedBox(height: 12),
          Text(
            arch.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.12,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            arch.description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 16,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  value: '${s.uniqueArtistCount}',
                  label: 'Artistas',
                  accent: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  value: '${s.uniqueTrackCount}',
                  label: 'Canciones',
                  accent: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  value: '${widget.playlistCount}',
                  label: 'Playlists',
                  accent: accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinalShareSlide(Color accent, InutilWrappedSummary s) {
    final hoursText = s.totalHours >= 1
        ? '${s.totalHours.toStringAsFixed(1)} h'
        : '${math.max(1, s.totalMinutes)} min';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InutilIcon(
                      InutilGlyph.sparkles,
                      size: 20,
                      color: accent,
                      filled: true,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'MI RESUMEN ${s.year}',
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _summaryRow('Artista #1', s.topArtist?.name ?? 'Inútil Music'),
                const SizedBox(height: 10),
                _summaryRow(
                  'Canción favorita',
                  s.topTrack?.title ?? 'Tu música',
                ),
                const SizedBox(height: 10),
                _summaryRow('Tiempo total', hoursText),
                const SizedBox(height: 10),
                _summaryRow(
                  'Tu vibra',
                  '${s.personalityArchetype.emoji} ${s.personalityArchetype.title}',
                ),
                const SizedBox(height: 14),
                Text(
                  'Gracias por ser parte de Inútil Music. ¡Vamos por un año todavía mejor lleno de música! 💛',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('inutil-wrapped-share'),
            onPressed: _shareSummary,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            icon: const Icon(Icons.share_rounded, size: 20),
            label: const Text(
              'Compartir mi Resumen',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _openSupport,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            icon: InutilIcon(
              InutilGlyph.heart,
              size: 18,
              color: accent,
              filled: true,
            ),
            label: const Text(
              'Apoyar al creador 💛',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required String value,
    required String label,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _fallbackArt(Color accent) {
    return ColoredBox(
      color: accent.withValues(alpha: 0.2),
      child: Center(
        child: InutilIcon(
          InutilGlyph.player,
          size: 46,
          color: accent,
          filled: true,
        ),
      ),
    );
  }
}
