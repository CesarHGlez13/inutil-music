import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/inutil_icons.dart';

/// Guía interactiva de bienvenida que se muestra una sola vez al entrar por
/// primera vez (y se puede repetir desde Ajustes → Acerca de).
///
/// Cada paso incluye una mini demostración que el usuario puede tocar o
/// deslizar para aprender los gestos reales de la app. El gesto atrás de
/// Android retrocede un paso y, en el primero, cierra la guía.
class InutilOnboardingTour extends StatefulWidget {
  const InutilOnboardingTour({this.inactivityDays = 15, super.key});

  /// Límite de días sin uso antes de la pausa automática (se explica con
  /// transparencia en el último paso).
  final int inactivityDays;

  static const String prefsKey = 'inutil_onboarding_completed_v1';

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKey) != true;
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, true);
  }

  static Future<void> show(BuildContext context, {int inactivityDays = 15}) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 650),
        reverseTransitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) =>
            InutilOnboardingTour(inactivityDays: inactivityDays),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.04, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    await markCompleted();
  }

  @override
  State<InutilOnboardingTour> createState() => _InutilOnboardingTourState();
}

class _TourStep {
  const _TourStep({
    required this.accent,
    required this.background,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.demo,
  });

  final Color accent;
  final Color background;
  final String eyebrow;
  final String title;
  final String body;
  final WidgetBuilder demo;
}

class _InutilOnboardingTourState extends State<InutilOnboardingTour> {
  final PageController _pages = PageController();
  int _index = 0;

  late final List<_TourStep> _steps = <_TourStep>[
    _TourStep(
      accent: const Color(0xFF34D399),
      background: const Color(0xFF0B1A16),
      eyebrow: 'BIENVENIDO',
      title: 'Hola, esto es\nInútil Music',
      body:
          'En menos de un minuto te mostramos lo esencial. Toca y desliza las '
          'demos: funcionan igual que en la app.',
      demo: (_) => const _WelcomeDemo(accent: Color(0xFF34D399)),
    ),
    _TourStep(
      accent: const Color(0xFF38BDF8),
      background: const Color(0xFF0A1622),
      eyebrow: 'INICIO Y BÚSQUEDA',
      title: 'Encuentra cualquier\ncanción al instante',
      body:
          'Escribe un artista, canción o álbum en Buscar. En Inicio tienes tus '
          'recientes y recomendaciones; desliza hacia abajo para refrescar.',
      demo: (_) => const _SearchDemo(accent: Color(0xFF38BDF8)),
    ),
    _TourStep(
      accent: const Color(0xFFC084FC),
      background: const Color(0xFF160E22),
      eyebrow: 'REPRODUCTOR',
      title: 'Letras, video y\ntemporizador',
      body:
          'Abre el reproductor tocando el mini-reproductor. Ahí encuentras letras '
          'sincronizadas, video Canvas y temporizador de sueño. Prueba el botón ▶.',
      demo: (_) => const _PlayerDemo(accent: Color(0xFFC084FC)),
    ),
    _TourStep(
      accent: const Color(0xFFFB923C),
      background: const Color(0xFF1E120A),
      eyebrow: 'GESTO RÁPIDO',
      title: 'Desliza para añadir\na la cola',
      body:
          'En cualquier lista, desliza una canción hacia la derecha y sonará '
          'justo después de la actual. ¡Inténtalo con la canción de abajo!',
      demo: (_) => const _SwipeDemo(accent: Color(0xFFFB923C)),
    ),
    _TourStep(
      accent: const Color(0xFFF472B6),
      background: const Color(0xFF200C19),
      eyebrow: 'TU BIBLIOTECA',
      title: 'Guarda lo que amas,\nnunca lo pierdes',
      body:
          'Toca el corazón para guardar en Favoritos y crea tus playlists. Todo '
          'se respalda en la nube: si cambias de teléfono, vuelve contigo.',
      demo: (_) => const _FavoriteDemo(accent: Color(0xFFF472B6)),
    ),
    _TourStep(
      accent: const Color(0xFF22D3EE),
      background: const Color(0xFF07181C),
      eyebrow: 'SIN INTERNET Y EN TU PC',
      title: 'Descarga y conecta\ntus dispositivos',
      body:
          'Descarga canciones para escucharlas sin datos y abre Inútil Music en '
          'tu PC con la misma cuenta para controlarla desde el teléfono.',
      demo: (_) => const _OfflineDemo(accent: Color(0xFF22D3EE)),
    ),
    _TourStep(
      accent: const Color(0xFFFBBF24),
      background: const Color(0xFF1C160A),
      eyebrow: 'HAZLA TUYA',
      title: 'Personaliza todo\ndesde Ajustes',
      body:
          'Cambia el estilo del reproductor, importa tus listas de Spotify o '
          'YouTube Music y revive tu Resumen del Año cuando quieras.',
      demo: (_) => const _PersonalizeDemo(accent: Color(0xFFFBBF24)),
    ),
    _TourStep(
      accent: const Color(0xFF8B9CFF),
      background: const Color(0xFF10132A),
      eyebrow: 'MANTÉN TU CUENTA ACTIVA',
      title: 'Tu acceso gratuito\nse cuida solo',
      body:
          'Los cupos gratuitos son limitados: si no abres la app durante '
          '${widget.inactivityDays} días, tu acceso se pausa automáticamente. '
          'Tus playlists siempre quedan a salvo en la nube.',
      demo: (_) => _ActiveDemo(
        accent: const Color(0xFF8B9CFF),
        days: widget.inactivityDays,
      ),
    ),
  ];

  bool get _isLast => _index == _steps.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    HapticFeedback.selectionClick();
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _goTo(_index + 1);
    }
  }

  void _finish() {
    HapticFeedback.mediumImpact();
    unawaited(InutilOnboardingTour.markCompleted());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_index];
    final media = MediaQuery.of(context);

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index > 0) _goTo(_index - 1);
      },
      child: Scaffold(
        key: const ValueKey('onboarding-tour'),
        backgroundColor: const Color(0xFF07080B),
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 750),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [step.background, const Color(0xFF07080B)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 10, 0),
                  child: Row(
                    children: [
                      Text(
                        '${_index + 1} de ${_steps.length}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: _isLast ? 0 : 1,
                        child: TextButton(
                          key: const ValueKey('onboarding-skip'),
                          onPressed: _isLast ? null : _finish,
                          child: Text(
                            'Saltar',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _steps.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _TourPage(
                      key: ValueKey('onboarding-page-$i'),
                      step: _steps[i],
                      compact: media.size.height < 700,
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _steps.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _index ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _index
                              ? step.accent
                              : Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                  child: Row(
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        child: _index == 0
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: IconButton.outlined(
                                  key: const ValueKey('onboarding-back'),
                                  onPressed: () => _goTo(_index - 1),
                                  icon: const Icon(
                                    Icons.arrow_back_rounded,
                                    color: Colors.white,
                                  ),
                                  style: IconButton.styleFrom(
                                    side: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.2),
                                    ),
                                    minimumSize: const Size(54, 54),
                                  ),
                                ),
                              ),
                      ),
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 450),
                          height: 54,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: step.accent.withValues(alpha: 0.35),
                                blurRadius: 22,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: FilledButton(
                            key: ValueKey(
                              _isLast ? 'onboarding-finish' : 'onboarding-next',
                            ),
                            onPressed: _next,
                            style: FilledButton.styleFrom(
                              backgroundColor: step.accent,
                              foregroundColor: const Color(0xFF07080B),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            child: Text(
                              _isLast ? '¡Empezar a escuchar!' : 'Siguiente',
                            ),
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
      ),
    );
  }
}

class _TourPage extends StatelessWidget {
  const _TourPage({required this.step, required this.compact, super.key});

  final _TourStep step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final demoMinHeight = math.min(
          constraints.maxHeight * (compact ? 0.36 : 0.42),
          250.0,
        );
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: demoMinHeight),
                  child: SizedBox(
                    width: double.infinity,
                    child: Center(child: step.demo(context)),
                  ),
                ),
                SizedBox(height: compact ? 18 : 28),
                Text(
                  step.eyebrow,
                  style: TextStyle(
                    color: step.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  step.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 26 : 30,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  step.body,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Mini demostraciones interactivas
// ---------------------------------------------------------------------------

class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: child,
    );
  }
}

class _FakeArt extends StatelessWidget {
  const _FakeArt({required this.colors, this.size = 46});

  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: InutilIcon(
          InutilGlyph.player,
          size: size * 0.42,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class _FakeTrackRow extends StatelessWidget {
  const _FakeTrackRow({
    required this.title,
    required this.artist,
    required this.colors,
    this.trailing,
  });

  final String title;
  final String artist;
  final List<Color> colors;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FakeArt(colors: colors),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _WelcomeDemo extends StatefulWidget {
  const _WelcomeDemo({required this.accent});

  final Color accent;

  @override
  State<_WelcomeDemo> createState() => _WelcomeDemoState();
}

class _WelcomeDemoState extends State<_WelcomeDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return AnimatedBuilder(
      animation: _spin,
      builder: (_, _) {
        final pulse = (math.sin(_spin.value * math.pi * 4) + 1) / 2;
        return SizedBox(
          width: 230,
          height: 230,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: _spin.value * math.pi * 2,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        accent.withValues(alpha: 0),
                        accent.withValues(alpha: 0.65),
                        const Color(0xFF38BDF8).withValues(alpha: 0.5),
                        accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: 196,
                height: 196,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF07080B),
                ),
              ),
              Container(
                width: 132 + 10 * pulse,
                height: 132 + 10 * pulse,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accent, const Color(0xFF0EA5E9)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35 + 0.2 * pulse),
                      blurRadius: 40,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Center(
                  child: InutilIcon(
                    InutilGlyph.player,
                    size: 58,
                    color: Colors.white,
                    filled: true,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SearchDemo extends StatefulWidget {
  const _SearchDemo({required this.accent});

  final Color accent;

  @override
  State<_SearchDemo> createState() => _SearchDemoState();
}

class _SearchDemoState extends State<_SearchDemo>
    with SingleTickerProviderStateMixin {
  static const List<List<String>> _queries = [
    ['Christian Nodal', 'Adiós Amor', 'Botella Tras Botella'],
    ['Mon Laferte', 'Amor Completo', 'Tu Falta de Querer'],
    ['Reyli Barba', 'Amor del Bueno', 'Desde que llegaste'],
  ];

  late final AnimationController _cycle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();
  int _queryIndex = 0;

  @override
  void initState() {
    super.initState();
    _cycle.addStatusListener((_) {});
    _cycle.addListener(_maybeAdvance);
  }

  double _last = 0;

  void _maybeAdvance() {
    if (_cycle.value < _last) {
      setState(() => _queryIndex = (_queryIndex + 1) % _queries.length);
    }
    _last = _cycle.value;
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final q = _queries[_queryIndex];
    return AnimatedBuilder(
      animation: _cycle,
      builder: (_, _) {
        final t = _cycle.value;
        final typed = (q[0].length * (t / 0.4)).clamp(0, q[0].length).floor();
        final showResults = t > 0.45;
        return _DemoCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    InutilIcon(InutilGlyph.search, size: 20, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${q[0].substring(0, typed)}${t < 0.45 && (t * 10).floor().isEven ? '|' : ''}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 380),
                opacity: showResults ? 1 : 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  offset: showResults ? Offset.zero : const Offset(0, 0.08),
                  child: Column(
                    children: [
                      _FakeTrackRow(
                        title: q[1],
                        artist: q[0],
                        colors: [accent, const Color(0xFF1E3A8A)],
                      ),
                      const SizedBox(height: 12),
                      _FakeTrackRow(
                        title: q[2],
                        artist: q[0],
                        colors: const [Color(0xFF0EA5E9), Color(0xFF312E81)],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayerDemo extends StatefulWidget {
  const _PlayerDemo({required this.accent});

  final Color accent;

  @override
  State<_PlayerDemo> createState() => _PlayerDemoState();
}

class _PlayerDemoState extends State<_PlayerDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bars = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _playing = false;

  @override
  void dispose() {
    _bars.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.lightImpact();
    setState(() => _playing = !_playing);
    if (_playing) {
      _bars.repeat();
    } else {
      _bars.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return _DemoCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _FakeArt(colors: [accent, const Color(0xFF4C1D95)], size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Amor del Bueno',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Reyli Barba',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: _bars,
                      builder: (_, _) => Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < 5; i++)
                            Container(
                              margin: const EdgeInsets.only(right: 3),
                              width: 4,
                              height: _playing
                                  ? 6 +
                                      14 *
                                          ((math.sin(
                                                    (_bars.value * 2 * math.pi) +
                                                        i * 1.3,
                                                  ) +
                                                  1) /
                                              2)
                                  : 4,
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                key: const ValueKey('onboarding-demo-play'),
                onTap: _toggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _playing ? accent : Colors.white,
                    boxShadow: [
                      if (_playing)
                        BoxShadow(
                          color: accent.withValues(alpha: 0.5),
                          blurRadius: 18,
                        ),
                    ],
                  ),
                  child: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: const Color(0xFF07080B),
                    size: 32,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 350),
            opacity: _playing ? 1 : 0.55,
            child: Text(
              _playing
                  ? '♪ Y es que este amor del bueno…'
                  : 'Toca ▶ para ver las letras en vivo',
              style: TextStyle(
                color: _playing ? Colors.white : Colors.white70,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(glyph: InutilGlyph.lyrics, label: 'Letras'),
              _Chip(glyph: InutilGlyph.live, label: 'Video Canvas'),
              _Chip(glyph: InutilGlyph.sleepTimer, label: 'Temporizador'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.glyph, required this.label});

  final InutilGlyph glyph;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InutilIcon(glyph, size: 15, color: Colors.white70),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeDemo extends StatefulWidget {
  const _SwipeDemo({required this.accent});

  final Color accent;

  @override
  State<_SwipeDemo> createState() => _SwipeDemoState();
}

class _SwipeDemoState extends State<_SwipeDemo>
    with SingleTickerProviderStateMixin {
  static const double _threshold = 90;

  late final AnimationController _hint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();
  double _drag = 0;
  bool _dragging = false;
  int _queued = 0;

  @override
  void dispose() {
    _hint.dispose();
    super.dispose();
  }

  void _onEnd() {
    final success = _drag >= _threshold;
    setState(() {
      _dragging = false;
      _drag = 0;
      if (success) _queued += 1;
    });
    if (success) HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return _DemoCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: accent.withValues(
                      alpha: (0.18 + (_drag / _threshold) * 0.5).clamp(0, 0.7),
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 18),
                    child: InutilIcon(
                      InutilGlyph.queue,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _hint,
                  builder: (_, child) {
                    final hintOffset = _dragging || _queued > 0
                        ? 0.0
                        : 26 *
                              math.sin(
                                (_hint.value.clamp(0, 0.5) / 0.5) * math.pi,
                              );
                    return Transform.translate(
                      offset: Offset(
                        _dragging ? _drag : hintOffset,
                        0,
                      ),
                      child: child,
                    );
                  },
                  child: GestureDetector(
                    key: const ValueKey('onboarding-demo-swipe'),
                    onHorizontalDragStart: (_) =>
                        setState(() => _dragging = true),
                    onHorizontalDragUpdate: (d) => setState(
                      () => _drag = (_drag + d.delta.dx).clamp(0, 160),
                    ),
                    onHorizontalDragEnd: (_) => _onEnd(),
                    onHorizontalDragCancel: _onEnd,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      color: const Color(0xFF1A1410),
                      child: _FakeTrackRow(
                        title: 'Sé Feliz X Mí',
                        artist: 'Christian Nodal',
                        colors: [accent, const Color(0xFF7C2D12)],
                        trailing: Icon(
                          Icons.drag_indicator_rounded,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Row(
              key: ValueKey(_queued),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _queued > 0
                      ? Icons.check_circle_rounded
                      : Icons.swipe_right_rounded,
                  size: 18,
                  color: _queued > 0 ? const Color(0xFF34D399) : Colors.white70,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _queued > 0
                        ? '¡Añadida a la cola! ($_queued)'
                        : 'Desliza la canción hacia la derecha →',
                    key: const ValueKey('onboarding-demo-swipe-label'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _queued > 0
                          ? const Color(0xFF34D399)
                          : Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteDemo extends StatefulWidget {
  const _FavoriteDemo({required this.accent});

  final Color accent;

  @override
  State<_FavoriteDemo> createState() => _FavoriteDemoState();
}

class _FavoriteDemoState extends State<_FavoriteDemo> {
  bool _liked = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return _DemoCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FakeTrackRow(
            title: 'Amor Completo',
            artist: 'Mon Laferte',
            colors: [accent, const Color(0xFF831843)],
            trailing: GestureDetector(
              key: const ValueKey('onboarding-demo-heart'),
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _liked = !_liked);
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: AnimatedScale(
                  scale: _liked ? 1.25 : 1,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.elasticOut,
                  child: InutilIcon(
                    InutilGlyph.heart,
                    size: 28,
                    filled: _liked,
                    color: _liked ? accent : Colors.white70,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _liked
                  ? accent.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  _liked ? Icons.cloud_done_rounded : Icons.touch_app_rounded,
                  color: _liked ? accent : Colors.white60,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _liked
                        ? 'Guardada en Favoritos y respaldada en la nube'
                        : 'Toca el corazón para guardarla',
                    style: TextStyle(
                      color: _liked ? Colors.white : Colors.white70,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineDemo extends StatefulWidget {
  const _OfflineDemo({required this.accent});

  final Color accent;

  @override
  State<_OfflineDemo> createState() => _OfflineDemoState();
}

class _OfflineDemoState extends State<_OfflineDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return _DemoCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _progress,
            builder: (_, _) {
              final value = (_progress.value / 0.8).clamp(0.0, 1.0);
              final done = value >= 1;
              return Row(
                children: [
                  InutilIcon(InutilGlyph.storage, size: 26, color: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          done ? 'Lista para escuchar sin internet' : 'Descargando…',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 5,
                            backgroundColor: Colors.white.withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    done ? Icons.download_done_rounded : Icons.downloading_rounded,
                    color: done ? const Color(0xFF34D399) : Colors.white60,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 18),
          Row(
            children: [
              InutilIcon(InutilGlyph.devices, size: 26, color: accent),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Teléfono  ⇄  PC con tu misma cuenta',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF34D399).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'Conectado',
                  style: TextStyle(
                    color: Color(0xFF34D399),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PersonalizeDemo extends StatefulWidget {
  const _PersonalizeDemo({required this.accent});

  final Color accent;

  @override
  State<_PersonalizeDemo> createState() => _PersonalizeDemoState();
}

class _PersonalizeDemoState extends State<_PersonalizeDemo> {
  static const List<Color> _swatches = [
    Color(0xFFFBBF24),
    Color(0xFF34D399),
    Color(0xFF38BDF8),
    Color(0xFFC084FC),
    Color(0xFFF472B6),
  ];
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final color = _swatches[_selected];
    return _DemoCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 420),
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.85), const Color(0xFF111114)],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: const Row(
              children: [
                InutilIcon(InutilGlyph.palette, size: 24, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tu estilo, tus colores',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < _swatches.length; i++)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selected = i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.only(right: 10),
                    width: i == _selected ? 34 : 28,
                    height: i == _selected ? 34 : 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _swatches[i],
                      border: Border.all(
                        color: Colors.white,
                        width: i == _selected ? 2.5 : 0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(glyph: InutilGlyph.link, label: 'Importar de Spotify'),
              _Chip(glyph: InutilGlyph.sources, label: 'YouTube Music'),
              _Chip(glyph: InutilGlyph.sparkles, label: 'Resumen del Año'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveDemo extends StatelessWidget {
  const _ActiveDemo({required this.accent, required this.days});

  final Color accent;
  final int days;

  @override
  Widget build(BuildContext context) {
    final shown = math.min(days, 15);
    return _DemoCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < shown; i++)
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: Duration(milliseconds: 300 + i * 70),
                  curve: Curves.easeOutBack,
                  builder: (_, v, child) => Transform.scale(scale: v, child: child),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? accent
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: i == 0
                        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Abre la app al menos una vez cada $days días',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Con escuchar una canción basta para mantener tu acceso.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
