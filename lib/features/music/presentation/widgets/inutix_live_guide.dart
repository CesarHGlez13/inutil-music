import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secciones reales de la app que el recorrido interactivo puede navegar en vivo.
enum InutixGuideSection {
  home,
  search,
  local,
  library,
  settings,
  player,
}

/// Anclas (`GlobalKey` y objetivos dinámicos) montadas sobre widgets reales de
/// `HomePage` y `PlayerPanel` para que el foco luminoso (*spotlight*) persiga
/// los botones auténticos de la interfaz.
class InutixGuideAnchors {
  InutixGuideAnchors._();

  static const String playerShareMomentId = 'player-share-moment';
  static const String playerMenuId = 'player-menu';

  static final GlobalKey connectButton = GlobalKey(debugLabel: 'guide-connect');
  static final GlobalKey accountButton = GlobalKey(debugLabel: 'guide-account');
  static final GlobalKey timeMachineChip = GlobalKey(
    debugLabel: 'guide-time-machine',
  );
  static final GlobalKey echoMemoryChip = GlobalKey(
    debugLabel: 'guide-echo-memory',
  );
  static final GlobalKey algorithmChip = GlobalKey(
    debugLabel: 'guide-algorithm',
  );
  static final GlobalKey listeningRoomsChip = GlobalKey(
    debugLabel: 'guide-listening-rooms',
  );
  static final GlobalKey miniPlayer = GlobalKey(
    debugLabel: 'guide-mini-player',
  );
  static final GlobalKey bottomNav = GlobalKey(debugLabel: 'guide-bottom-nav');
  static final GlobalKey sideNav = GlobalKey(debugLabel: 'guide-side-nav');

  static final Map<String, List<BuildContext>> _dynamicTargets =
      <String, List<BuildContext>>{};

  static void registerTarget(String id, BuildContext context) {
    final list = _dynamicTargets.putIfAbsent(id, () => <BuildContext>[]);
    list.remove(context);
    list.add(context);
  }

  static void unregisterTarget(String id, BuildContext context) {
    final list = _dynamicTargets[id];
    if (list == null) return;
    list.remove(context);
    if (list.isEmpty) {
      _dynamicTargets.remove(id);
    }
  }

  static List<BuildContext> targetsFor(String id) {
    final list = _dynamicTargets[id];
    if (list == null || list.isEmpty) return const <BuildContext>[];
    return List<BuildContext>.unmodifiable(list.reversed);
  }

  @visibleForTesting
  static void clearDynamicTargetsForTesting() {
    _dynamicTargets.clear();
  }
}

/// Registra un widget real como objetivo de foco sin riesgo de colisiones de
/// `GlobalKey` cuando coexisten transiciones (`AnimatedSwitcher`, desktop/móvil).
class InutixGuideAnchorTarget extends StatefulWidget {
  const InutixGuideAnchorTarget({
    super.key,
    required this.id,
    required this.child,
  });

  final String id;
  final Widget child;

  @override
  State<InutixGuideAnchorTarget> createState() =>
      _InutixGuideAnchorTargetState();
}

class _InutixGuideAnchorTargetState extends State<InutixGuideAnchorTarget> {
  @override
  void initState() {
    super.initState();
    InutixGuideAnchors.registerTarget(widget.id, context);
  }

  @override
  void didUpdateWidget(covariant InutixGuideAnchorTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      InutixGuideAnchors.unregisterTarget(oldWidget.id, context);
      InutixGuideAnchors.registerTarget(widget.id, context);
    }
  }

  @override
  void dispose() {
    InutixGuideAnchors.unregisterTarget(widget.id, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Consejo contextual en tiempo real que aparece una sola vez al descubrir una
/// sección avanzada durante el uso cotidiano de la app.
@immutable
class InutixContextualTip {
  const InutixContextualTip({
    required this.id,
    required this.section,
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
    this.badge = 'TIP EN VIVO',
  });

  final String id;
  final InutixGuideSection section;
  final IconData icon;
  final Color accent;
  final String title;
  final String body;
  final String badge;
}

/// Controlador singleton que coordina:
/// 1. El **Recorrido Interactivo Cinemático en Vivo** (spotlight real sobre la app).
/// 2. Los **Consejos Contextuales en Tiempo Real** mientras el usuario explora.
class InutixLiveGuideController extends ChangeNotifier {
  InutixLiveGuideController._();
  static final InutixLiveGuideController instance =
      InutixLiveGuideController._();

  static const String tourCompletedPrefsKey =
      'inutil_onboarding_completed_v1';
  static const String liveTourVersionPrefsKey =
      'inutix_live_spotlight_tour_v2_done';
  static const String tipsEnabledPrefsKey = 'inutix_live_tips_enabled_v1';
  static const String _tipPrefix = 'inutix_live_tip_seen_';

  /// Catálogo de micro-consejos contextuales en tiempo real.
  static const List<InutixContextualTip> contextualTips = <InutixContextualTip>[
    InutixContextualTip(
      id: 'search_swipe_queue',
      section: InutixGuideSection.search,
      icon: Icons.swipe_right_rounded,
      accent: Color(0xFF38BDF8),
      title: 'Gesto rápido en resultados',
      body:
          'Desliza cualquier canción hacia la derecha para ponerla «A continuación» sin cortar lo que está sonando.',
    ),
    InutixContextualTip(
      id: 'local_offline_hifi',
      section: InutixGuideSection.local,
      icon: Icons.offline_bolt_rounded,
      accent: Color(0xFF20E09B),
      title: 'Tu bóveda sin internet',
      body:
          'Todas tus descargas viven aquí en calidad original y se reproducen al instante incluso en modo avión.',
    ),
    InutixContextualTip(
      id: 'library_cloud_import',
      section: InutixGuideSection.library,
      icon: Icons.cloud_done_rounded,
      accent: Color(0xFFFBBF24),
      title: 'Importa desde Spotify o CSV',
      body:
          'Trae tus playlists externas en segundos. Tus favoritos y listas se sincronizan automáticamente en tu cuenta Inutix.',
    ),
    InutixContextualTip(
      id: 'player_share_moment',
      section: InutixGuideSection.player,
      icon: Icons.movie_creation_rounded,
      accent: Color(0xFFFF3D71),
      badge: 'FUNCIÓN ESTRELLA',
      title: 'Compartir momento en 1080p 60 fps',
      body:
          'Toca Compartir o el menú ⋯ → «Compartir momento» para exportar un video de 5–30 s con letras karaoke, Canvas animado o tu Echo Memory listo para WhatsApp HD, Instagram y TikTok sin grabar pantalla.',
    ),
  ];

  void Function(InutixGuideSection section)? _sectionNavigator;
  InutixGuideSection Function()? _currentSectionReader;
  VoidCallback? _scrollHomeToTop;
  OverlayEntry? _activeOverlay;
  Completer<void>? _activeTourCompleter;

  bool _tourActive = false;
  bool get isTourActive => _tourActive;

  bool get isAttached => _sectionNavigator != null;

  InutixContextualTip? _activeTip;
  InutixContextualTip? get activeTip => _tourActive ? null : _activeTip;

  bool _tipsEnabled = true;
  bool get tipsEnabled => _tipsEnabled;

  final Set<String> _seenTipIds = <String>{};
  bool _prefsLoaded = false;

  /// Registra el host real (`HomePage`) para permitir navegación y scroll en vivo.
  void attachHost({
    required void Function(InutixGuideSection section) onSelectSection,
    required InutixGuideSection Function() readCurrentSection,
    VoidCallback? onScrollHomeToTop,
  }) {
    _sectionNavigator = onSelectSection;
    _currentSectionReader = readCurrentSection;
    _scrollHomeToTop = onScrollHomeToTop;
    unawaited(_ensurePrefsLoaded());
  }

  void detachHost(void Function(InutixGuideSection section) onSelectSection) {
    if (_sectionNavigator == onSelectSection) {
      _sectionNavigator = null;
      _currentSectionReader = null;
      _scrollHomeToTop = null;
      _removeOverlay();
    }
  }

  Future<void> _ensurePrefsLoaded() async {
    if (_prefsLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _tipsEnabled = prefs.getBool(tipsEnabledPrefsKey) ?? true;
      for (final tip in contextualTips) {
        if (prefs.getBool('$_tipPrefix${tip.id}') == true) {
          _seenTipIds.add(tip.id);
        }
      }
      _prefsLoaded = true;
    } catch (_) {
      _prefsLoaded = true;
    }
  }

  /// Indica si conviene iniciar el recorrido interactivo en el primer arranque.
  Future<bool> shouldAutoLaunchTour() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(tourCompletedPrefsKey) != true;
    } catch (_) {
      return false;
    }
  }

  Future<void> markTourCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(tourCompletedPrefsKey, true);
      await prefs.setBool(liveTourVersionPrefsKey, true);
    } catch (_) {}
  }

  /// Notifica que el usuario entró en [section] durante uso real.
  /// Si hay un tip contextual pendiente para esa sección y el tour no está
  /// activo, lo muestra discretamente con animación Liquid Glass.
  Future<void> notifySectionEntered(InutixGuideSection section) async {
    await _ensurePrefsLoaded();
    if (_tourActive || !_tipsEnabled) {
      if (_activeTip != null && _activeTip!.section != section) {
        _activeTip = null;
        notifyListeners();
      }
      return;
    }

    InutixContextualTip? match;
    for (final tip in contextualTips) {
      if (tip.section == section && !_seenTipIds.contains(tip.id)) {
        match = tip;
        break;
      }
    }

    if (_activeTip?.id != match?.id) {
      _activeTip = match;
      notifyListeners();
    }
  }

  /// Marca el consejo activo como visto y lo oculta suavemente.
  Future<void> dismissActiveTip() async {
    final tip = _activeTip;
    if (tip == null) return;
    _seenTipIds.add(tip.id);
    _activeTip = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_tipPrefix${tip.id}', true);
    } catch (_) {}
  }

  /// Desactiva por completo los consejos contextuales en tiempo real.
  Future<void> disableAllContextualTips() async {
    _tipsEnabled = false;
    _activeTip = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(tipsEnabledPrefsKey, false);
    } catch (_) {}
  }

  /// Reactiva y reinicia todos los consejos contextuales en tiempo real.
  Future<void> resetContextualTips() async {
    _tipsEnabled = true;
    _seenTipIds.clear();
    _activeTip = null;
    _prefsLoaded = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(tipsEnabledPrefsKey, true);
      for (final tip in contextualTips) {
        await prefs.remove('$_tipPrefix${tip.id}');
      }
    } catch (_) {}
  }

  void navigateTo(InutixGuideSection section) {
    _sectionNavigator?.call(section);
  }

  void scrollHomeToTop() {
    _scrollHomeToTop?.call();
  }

  InutixGuideSection get currentSection =>
      _currentSectionReader?.call() ?? InutixGuideSection.home;

  /// Lanza el **Recorrido Interactivo Cinemático en Vivo** sobre la app real.
  /// Devuelve `true` si se pudo montar sobre el `Overlay` del host real.
  Future<bool> startLiveTour(
    BuildContext context, {
    int inactivityDays = 15,
  }) async {
    if (!isAttached) return false;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return false;

    if (_tourActive) {
      await _activeTourCompleter?.future;
      return true;
    }

    _tourActive = true;
    _activeTip = null;
    notifyListeners();

    final originSection = currentSection;
    // Empezamos siempre desde Inicio (y arriba del todo) para que las cápsulas
    // y el encabezado estén listos desde el primer frame.
    navigateTo(InutixGuideSection.home);
    scrollHomeToTop();

    final completer = Completer<void>();
    _activeTourCompleter = completer;

    final entry = OverlayEntry(
      builder: (_) => _InutixLiveSpotlightOverlay(
        inactivityDays: inactivityDays,
        onFinished: (bool returnHome) {
          _removeOverlay();
          if (returnHome) {
            navigateTo(InutixGuideSection.home);
          } else {
            navigateTo(originSection);
          }
          unawaited(markTourCompleted());
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      ),
    );
    _activeOverlay = entry;
    overlay.insert(entry);

    await completer.future;
    return true;
  }

  void _removeOverlay() {
    _activeOverlay?.remove();
    _activeOverlay = null;
    if (_tourActive) {
      _tourActive = false;
      notifyListeners();
    }
    if (_activeTourCompleter != null && !_activeTourCompleter!.isCompleted) {
      _activeTourCompleter!.complete();
    }
    _activeTourCompleter = null;
  }

  @visibleForTesting
  void resetForTesting() {
    _removeOverlay();
    _sectionNavigator = null;
    _currentSectionReader = null;
    _scrollHomeToTop = null;
    _activeTip = null;
    _seenTipIds.clear();
    _tipsEnabled = true;
    _prefsLoaded = false;
    InutixGuideAnchors.clearDynamicTargetsForTesting();
  }
}

/// Paso individual del recorrido interactivo en vivo.
class _LiveTourStep {
  const _LiveTourStep({
    required this.id,
    required this.section,
    required this.accent,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.highlights,
    this.anchorKey,
    this.fallbackAnchorKey,
    this.anchorId,
    this.fallbackAnchorId,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = 22,
    this.ensureHorizontalScroll = false,
    this.isHeroWelcome = false,
    this.showShareMomentStudioPreview = false,
    this.nextLabel,
    this.actionHint,
  });

  final String id;
  final InutixGuideSection section;
  final Color accent;
  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;
  final List<String> highlights;
  final GlobalKey? anchorKey;
  final GlobalKey? fallbackAnchorKey;
  final String? anchorId;
  final String? fallbackAnchorId;
  final EdgeInsets padding;
  final double borderRadius;
  final bool ensureHorizontalScroll;
  final bool isHeroWelcome;
  final bool showShareMomentStudioPreview;
  final String? nextLabel;
  final String? actionHint;
}

class _InutixLiveSpotlightOverlay extends StatefulWidget {
  const _InutixLiveSpotlightOverlay({
    required this.inactivityDays,
    required this.onFinished,
  });

  final int inactivityDays;
  final void Function(bool returnHome) onFinished;

  @override
  State<_InutixLiveSpotlightOverlay> createState() =>
      _InutixLiveSpotlightOverlayState();
}

class _InutixLiveSpotlightOverlayState
    extends State<_InutixLiveSpotlightOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final AnimationController _morphCtrl;
  late final AnimationController _ambientCtrl;

  int _index = 0;
  int _prepareGeneration = 0;
  Rect? _fromRect;
  Rect? _targetRect;
  double _fromRadius = 26;
  double _targetRadius = 26;
  bool _closing = false;

  late final List<_LiveTourStep> _steps = <_LiveTourStep>[
    const _LiveTourStep(
      id: 'welcome',
      section: InutixGuideSection.home,
      accent: Color(0xFF20E09B),
      icon: Icons.auto_awesome_rounded,
      eyebrow: 'RECORRIDO EN VIVO',
      title: 'Descubre el poder real\nde Inutix Music',
      body:
          'Este recorrido se desplaza directamente sobre tu app en tiempo real '
          'para enseñarte sus funciones más épicas en menos de un minuto.',
      highlights: <String>[
        'Inutix Connect',
        'Compartir Momento',
        'Máquina del Tiempo',
        'Echo Memory',
        'Salas en vivo',
      ],
      isHeroWelcome: true,
    ),
    _LiveTourStep(
      id: 'connect',
      section: InutixGuideSection.home,
      accent: const Color(0xFF22D3EE),
      icon: Icons.devices_rounded,
      eyebrow: 'INUTIX CONNECT',
      title: 'Tu PC y tu celular,\nun solo reproductor',
      body:
          'Abre Inutix Music en tu computadora y contrólala desde aquí al '
          'instante: pausa, cambia de canción o transfiere la sesión sin cortes.',
      highlights: <String>['Sincronía instantánea', 'Control remoto LAN/Nube'],
      anchorKey: InutixGuideAnchors.connectButton,
      padding: const EdgeInsets.all(7),
      borderRadius: 999,
      actionHint: 'Toca aquí en cualquier momento para ver tus dispositivos',
    ),
    _LiveTourStep(
      id: 'time_machine',
      section: InutixGuideSection.home,
      accent: const Color(0xFFA78BFA),
      icon: Icons.history_toggle_off_rounded,
      eyebrow: 'MÁQUINA DEL TIEMPO',
      title: 'Viaja a cualquier mes\nde tu historia musical',
      body:
          'Revive exactamente las canciones, artistas y vibras que escuchabas '
          'en cualquier mes o año anterior con una playlist generada al vuelo.',
      highlights: <String>['Viaje por mes y año', 'Top personal instantáneo'],
      anchorKey: InutixGuideAnchors.timeMachineChip,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      borderRadius: 999,
      ensureHorizontalScroll: true,
    ),
    _LiveTourStep(
      id: 'echo_memory',
      section: InutixGuideSection.home,
      accent: const Color(0xFFF472B6),
      icon: Icons.auto_stories_rounded,
      eyebrow: 'ECHO MEMORY',
      title: 'Guarda recuerdos dentro\nde cada canción',
      body:
          'Anota un momento, un lugar o una dedicatoria ligada a tu canción '
          'favorita. Cada vez que vuelva a sonar, tu recuerdo reaparece contigo.',
      highlights: <String>['Diario musical privado', 'Respaldo en tu cuenta'],
      anchorKey: InutixGuideAnchors.echoMemoryChip,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      borderRadius: 999,
      ensureHorizontalScroll: true,
    ),
    _LiveTourStep(
      id: 'algorithm_control',
      section: InutixGuideSection.home,
      accent: const Color(0xFF20E09B),
      icon: Icons.tune_rounded,
      eyebrow: 'CONTROL DEL ALGORITMO',
      title: 'Tú mandas sobre lo que\nte recomendamos',
      body:
          'Activa el modo «Sin algoritmo», silencia artistas que no quieres '
          'volver a escuchar o ajusta la intensidad del descubrimiento a tu gusto.',
      highlights: <String>['Modo sin algoritmo', 'Bloqueo de artistas'],
      anchorKey: InutixGuideAnchors.algorithmChip,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      borderRadius: 999,
      ensureHorizontalScroll: true,
    ),
    _LiveTourStep(
      id: 'listening_rooms',
      section: InutixGuideSection.home,
      accent: const Color(0xFF1ED760),
      icon: Icons.groups_rounded,
      eyebrow: 'SALAS EN VIVO',
      title: 'Escucha al mismo segundo\njunto con tus amigos',
      body:
          'Crea una sala privada con código y comparte tu cola en tiempo real: '
          'todos escuchan el mismo beat sincronizado aunque estén a kilómetros.',
      highlights: <String>['Código de sala rápido', 'Sincronía milimétrica'],
      anchorKey: InutixGuideAnchors.listeningRoomsChip,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      borderRadius: 999,
      ensureHorizontalScroll: true,
    ),
    _LiveTourStep(
      id: 'mini_player',
      section: InutixGuideSection.home,
      accent: const Color(0xFFFB923C),
      icon: Icons.music_note_rounded,
      eyebrow: 'REPRODUCTOR CINEMÁTICO',
      title: 'Letras karaoke en vivo\ny Detector de versiones',
      body:
          'Toca el mini-reproductor para expandir la vista completa con Canvas '
          'animado, letras sincronizadas palabra por palabra y versiones '
          'Acústica, En vivo o Remix.',
      highlights: <String>[
        'Letras karaoke',
        'Detector de versiones',
        'Canvas animado',
      ],
      anchorKey: InutixGuideAnchors.miniPlayer,
      fallbackAnchorKey: InutixGuideAnchors.bottomNav,
      padding: const EdgeInsets.all(6),
      borderRadius: 28,
      nextLabel: 'Abrir reproductor',
    ),
    const _LiveTourStep(
      id: 'share_moment',
      section: InutixGuideSection.player,
      accent: Color(0xFFFF3D71),
      icon: Icons.movie_creation_rounded,
      eyebrow: 'COMPARTIR MOMENTO · STUDIO',
      title: 'Exporta clips en 1080p\n60 fps desde el reproductor',
      body:
          'Toca Compartir (o el menú ⋯) → «Compartir momento». Recorta 5–30 s '
          'con letras karaoke, Canvas o tu Echo Memory para WhatsApp HD, '
          'Instagram y TikTok sin grabar pantalla.',
      highlights: <String>[
        '5–30 s · MP4 1080p 60 fps',
        'Letras o Canvas',
        'WhatsApp HD · Reels · TikTok',
      ],
      anchorId: InutixGuideAnchors.playerShareMomentId,
      fallbackAnchorId: InutixGuideAnchors.playerMenuId,
      padding: EdgeInsets.all(8),
      borderRadius: 999,
      showShareMomentStudioPreview: true,
    ),
    _LiveTourStep(
      id: 'search_tab',
      section: InutixGuideSection.search,
      accent: const Color(0xFF38BDF8),
      icon: Icons.search_rounded,
      eyebrow: 'BÚSQUEDA + RADIO INFINITA',
      title: 'Encuentra todo al instante\ny desliza a la cola',
      body:
          'Ya estamos en Buscar: escribe cualquier canción, álbum o artista. '
          'Desliza una pista hacia la derecha para ponerla «A continuación».',
      highlights: <String>['Desliza → A continuación', 'Audio Hi-Fi y video'],
      anchorKey: InutixGuideAnchors.bottomNav,
      fallbackAnchorKey: InutixGuideAnchors.sideNav,
      padding: const EdgeInsets.all(6),
      borderRadius: 26,
    ),
    _LiveTourStep(
      id: 'library_tab',
      section: InutixGuideSection.library,
      accent: const Color(0xFFFBBF24),
      icon: Icons.library_music_rounded,
      eyebrow: 'BIBLIOTECA Y OFFLINE',
      title: 'Importa Spotify/CSV\ny escucha sin internet',
      body:
          'Aquí viven tus playlists, favoritos y descargas offline. Todo se '
          'respalda en tu cuenta Inutix para que nunca pierdas tu música.',
      highlights: <String>['Importador Spotify/CSV', 'Modo sin internet'],
      anchorKey: InutixGuideAnchors.bottomNav,
      fallbackAnchorKey: InutixGuideAnchors.sideNav,
      padding: const EdgeInsets.all(6),
      borderRadius: 26,
    ),
    _LiveTourStep(
      id: 'settings_finish',
      section: InutixGuideSection.settings,
      accent: const Color(0xFF818CF8),
      icon: Icons.auto_fix_high_rounded,
      eyebrow: 'PERSONALIZACIÓN Y CUENTA',
      title: 'Hazla 100 % tuya\ny activa tips en vivo',
      body:
          'En Ajustes cambias temas Liquid Glass, calidad de audio y puedes '
          'repetir esta guía cuando quieras. Recuerda abrir la app al menos '
          'una vez cada ${widget.inactivityDays} días para mantener tu acceso activo.',
      highlights: <String>[
        'Liquid Glass',
        'Consejos contextuales',
        'Respaldo en la nube',
      ],
      anchorKey: InutixGuideAnchors.bottomNav,
      fallbackAnchorKey: InutixGuideAnchors.sideNav,
      padding: const EdgeInsets.all(6),
      borderRadius: 26,
    ),
  ];

  _LiveTourStep get _step => _steps[_index];
  bool get _isLast => _index == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    _morphCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 540),
    );
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareStep(_index, initial: true);
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _morphCtrl.dispose();
    _ambientCtrl.dispose();
    super.dispose();
  }

  Future<void> _prepareStep(int index, {bool initial = false}) async {
    if (!mounted) return;
    final gen = ++_prepareGeneration;
    final step = _steps[index];
    final guide = InutixLiveGuideController.instance;
    final previousSection = guide.currentSection;
    final sectionChanged = previousSection != step.section;
    final involvesPlayerTransition =
        sectionChanged &&
        (previousSection == InutixGuideSection.player ||
            step.section == InutixGuideSection.player);

    // 1. Navegar realmente a la sección de este paso.
    if (sectionChanged) {
      guide.navigateTo(step.section);
    }
    if (step.section == InutixGuideSection.home && !step.ensureHorizontalScroll) {
      guide.scrollHomeToTop();
    }

    // Esperar a que termine la transición del reproductor abierto (320 ms)
    // antes de medir las coordenadas finales de sus botones reales.
    if (involvesPlayerTransition) {
      await Future<void>.delayed(const Duration(milliseconds: 380));
      if (!mounted || gen != _prepareGeneration) return;
    }

    // Esperar un frame para que el árbol destino termine su layout.
    await _waitNextFrame();
    if (!mounted || gen != _prepareGeneration) return;

    // 2. Si el chip está en una barra horizontal, llevarlo al centro visible.
    if (step.ensureHorizontalScroll && step.anchorKey?.currentContext != null) {
      try {
        await Scrollable.ensureVisible(
          step.anchorKey!.currentContext!,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: 0.5,
        );
      } catch (_) {}
      await _waitNextFrame();
      if (!mounted || gen != _prepareGeneration) return;
    }

    // 3. Medir el Rect real en pantalla del widget objetivo (GlobalKey o ID dinámico).
    final measured = step.isHeroWelcome
        ? null
        : _measureAnchorById(step.anchorId, step.padding) ??
            _measureAnchor(step.anchorKey, step.padding) ??
            _measureAnchorById(step.fallbackAnchorId, step.padding) ??
            _measureAnchor(step.fallbackAnchorKey, step.padding);

    final prevRect = _currentAnimatedRect();
    final prevRadius = _currentAnimatedRadius();

    setState(() {
      _fromRect = initial ? measured : prevRect;
      _targetRect = measured;
      _fromRadius = initial ? step.borderRadius : prevRadius;
      _targetRadius = step.borderRadius;
    });

    _morphCtrl
      ..reset()
      ..forward();
  }

  Future<void> _waitNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  Rect? _measureAnchorById(String? id, EdgeInsets padding) {
    if (id == null) return null;
    for (final ctx in InutixGuideAnchors.targetsFor(id)) {
      if (!ctx.mounted) continue;
      final measured = _measureContext(ctx, padding);
      if (measured != null) return measured;
    }
    return null;
  }

  Rect? _measureAnchor(GlobalKey? key, EdgeInsets padding) {
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    return _measureContext(ctx, padding);
  }

  Rect? _measureContext(BuildContext ctx, EdgeInsets padding) {
    final renderObj = ctx.findRenderObject();
    if (renderObj is! RenderBox || !renderObj.hasSize || !renderObj.attached) {
      return null;
    }
    final topLeft = renderObj.localToGlobal(Offset.zero);
    final rect = topLeft & renderObj.size;
    if (rect.width <= 0 || rect.height <= 0) return null;
    final screen = MediaQuery.sizeOf(context);
    // Verificar que el rect intersecta razonablemente la pantalla.
    if (rect.right < 0 ||
        rect.left > screen.width ||
        rect.bottom < 0 ||
        rect.top > screen.height) {
      return null;
    }
    final inflated = Rect.fromLTRB(
      (rect.left - padding.left).clamp(4.0, screen.width - 4.0),
      (rect.top - padding.top).clamp(4.0, screen.height - 4.0),
      (rect.right + padding.right).clamp(4.0, screen.width - 4.0),
      (rect.bottom + padding.bottom).clamp(4.0, screen.height - 4.0),
    );
    return inflated;
  }

  Rect? _currentAnimatedRect() {
    final t = Curves.easeOutExpo.transform(_morphCtrl.value);
    if (_targetRect == null) return null;
    if (_fromRect == null) return _targetRect;
    return Rect.lerp(_fromRect, _targetRect, t);
  }

  double _currentAnimatedRadius() {
    final t = Curves.easeOutExpo.transform(_morphCtrl.value);
    return lerpDouble(_fromRadius, _targetRadius, t) ?? _targetRadius;
  }

  void _goTo(int nextIndex) {
    if (_closing || nextIndex < 0 || nextIndex >= _steps.length) return;
    HapticFeedback.selectionClick();
    setState(() => _index = nextIndex);
    unawaited(_prepareStep(nextIndex));
  }

  void _next() {
    if (_isLast) {
      _close(returnHome: true);
    } else {
      _goTo(_index + 1);
    }
  }

  void _back() {
    if (_index > 0) {
      _goTo(_index - 1);
    }
  }

  Future<void> _close({required bool returnHome}) async {
    if (_closing) return;
    _closing = true;
    HapticFeedback.mediumImpact();
    try {
      await _entranceCtrl.reverse();
    } catch (_) {}
    if (mounted) {
      widget.onFinished(returnHome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final step = _step;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index > 0) {
          _back();
        } else {
          unawaited(_close(returnHome: true));
        }
      },
      child: Material(
        key: const ValueKey('inutix-live-spotlight-tour'),
        type: MaterialType.transparency,
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: _entranceCtrl,
            curve: Curves.easeOutCubic,
          ),
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_morphCtrl, _ambientCtrl]),
            builder: (context, _) {
              final spotlight = _currentAnimatedRect();
              final radius = _currentAnimatedRadius();
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // 1. Fondo cinemático con recorte luminoso y aura animada.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      // Tocar fuera del recorte avanza suavemente solo si no es
                      // la pantalla de bienvenida.
                    },
                    child: CustomPaint(
                      size: size,
                      painter: _SpotlightBackdropPainter(
                        spotlightRect: spotlight,
                        borderRadius: radius,
                        accent: step.accent,
                        phase: _ambientCtrl.value,
                        backdropAlpha: step.isHeroWelcome ? 0.86 : 0.78,
                      ),
                    ),
                  ),

                  // 2. Tarjeta Liquid Glass posicionada inteligentemente.
                  _buildPositionedCard(
                    context: context,
                    size: size,
                    padding: media.padding,
                    step: step,
                    spotlight: spotlight,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPositionedCard({
    required BuildContext context,
    required Size size,
    required EdgeInsets padding,
    required _LiveTourStep step,
    required Rect? spotlight,
  }) {
    final maxCardWidth = math.min(430.0, size.width - 28.0);
    final card = _GlassTourCard(
      step: step,
      index: _index,
      total: _steps.length,
      isLast: _isLast,
      ambientPhase: _ambientCtrl.value,
      onSkip: () => _close(returnHome: true),
      onBack: _index > 0 ? _back : null,
      onNext: _next,
    );

    if (step.isHeroWelcome || spotlight == null) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxCardWidth,
                maxHeight: size.height - padding.vertical - 32,
              ),
              child: card,
            ),
          ),
        ),
      );
    }

    // Decidir si la tarjeta luce mejor arriba o abajo del elemento iluminado.
    final safeTop = padding.top + 14.0;
    final safeBottom = size.height - padding.bottom - 14.0;
    final spaceAbove = (spotlight.top - safeTop - 22.0).clamp(0.0, size.height);
    final spaceBelow =
        (safeBottom - spotlight.bottom - 22.0).clamp(0.0, size.height);
    final placeBelow = spaceBelow >= spaceAbove;
    final availableHeight = math.max(
      200.0,
      (placeBelow ? spaceBelow : spaceAbove),
    );

    final horizontalLeft = ((size.width - maxCardWidth) / 2.0)
        .clamp(14.0, math.max(14.0, size.width - maxCardWidth - 14.0))
        .toDouble();

    // Posición horizontal del puntero apuntando al centro del elemento real.
    final pointerX = (spotlight.center.dx - horizontalLeft)
        .clamp(32.0, maxCardWidth - 32.0)
        .toDouble();

    final double? topPos = placeBelow
        ? (spotlight.bottom + 18.0)
            .clamp(safeTop, math.max(safeTop, safeBottom - 220.0))
            .toDouble()
        : null;
    final double? bottomPos = placeBelow
        ? null
        : (size.height - spotlight.top + 18.0)
            .clamp(
              padding.bottom + 14.0,
              math.max(padding.bottom + 14.0, size.height - safeTop - 220.0),
            )
            .toDouble();

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutExpo,
      left: horizontalLeft,
      width: maxCardWidth,
      top: topPos,
      bottom: bottomPos,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: availableHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (placeBelow)
              _SpotlightConnector(
                offsetX: pointerX,
                accent: step.accent,
                pointingUp: true,
              ),
            Flexible(
              child: card,
            ),
            if (!placeBelow)
              _SpotlightConnector(
                offsetX: pointerX,
                accent: step.accent,
                pointingUp: false,
              ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightConnector extends StatelessWidget {
  const _SpotlightConnector({
    required this.offsetX,
    required this.accent,
    required this.pointingUp,
  });

  final double offsetX;
  final Color accent;
  final bool pointingUp;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: offsetX - 9,
            top: pointingUp ? 2 : 0,
            child: CustomPaint(
              size: const Size(18, 10),
              painter: _ConnectorTrianglePainter(
                accent: accent,
                pointingUp: pointingUp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectorTrianglePainter extends CustomPainter {
  const _ConnectorTrianglePainter({
    required this.accent,
    required this.pointingUp,
  });

  final Color accent;
  final bool pointingUp;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointingUp) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close();
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: 0.92)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _ConnectorTrianglePainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.pointingUp != pointingUp;
}

class _SpotlightBackdropPainter extends CustomPainter {
  const _SpotlightBackdropPainter({
    required this.spotlightRect,
    required this.borderRadius,
    required this.accent,
    required this.phase,
    required this.backdropAlpha,
  });

  final Rect? spotlightRect;
  final double borderRadius;
  final Color accent;
  final double phase;
  final double backdropAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final rect = spotlightRect;

    if (rect == null) {
      // Fondo oscuro con sutil aura radial para la bienvenida hero.
      final bgPaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.25),
          radius: 0.95,
          colors: <Color>[
            accent.withValues(alpha: 0.16),
            const Color(0xFF05070C).withValues(alpha: backdropAlpha),
          ],
        ).createShader(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, bgPaint);
      return;
    }

    final effectiveRadius = math.min(
      borderRadius,
      math.min(rect.width, rect.height) / 2,
    );
    final holeRRect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(effectiveRadius),
    );
    final holePath = Path()..addRRect(holeRRect);
    final overlayPath = Path.combine(PathOperation.difference, full, holePath);

    canvas.drawPath(
      overlayPath,
      Paint()..color = const Color(0xFF04060B).withValues(alpha: backdropAlpha),
    );

    // 1. Dos anillos sonar expansivos y respirantes alrededor del recorte real.
    for (var i = 0; i < 2; i++) {
      final p = (phase + i * 0.5) % 1.0;
      final inflate = 3.0 + p * 18.0;
      final alpha = (1.0 - p) * (1.0 - p) * 0.48;
      final pulseRRect = RRect.fromRectAndRadius(
        rect.inflate(inflate),
        Radius.circular(effectiveRadius + inflate * 0.65),
      );
      canvas.drawRRect(
        pulseRRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * (1.0 - p * 0.5)
          ..color = accent.withValues(alpha: alpha),
      );
    }

    // 2. Resplandor suave exterior.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(2.0),
        Radius.circular(effectiveRadius + 2.0),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9)
        ..color = accent.withValues(alpha: 0.45),
    );

    // 3. Borde prismático líquido giratorio (efecto Apple Intelligence / Liquid Glass).
    final sweepShader = SweepGradient(
      colors: <Color>[
        accent.withValues(alpha: 0.35),
        accent,
        Colors.white,
        accent,
        accent.withValues(alpha: 0.35),
      ],
      stops: const <double>[0.0, 0.28, 0.5, 0.72, 1.0],
      transform: GradientRotation(phase * math.pi * 2),
    ).createShader(rect.inflate(6));

    canvas.drawRRect(
      holeRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = sweepShader,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightBackdropPainter oldDelegate) =>
      oldDelegate.spotlightRect != spotlightRect ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.accent != accent ||
      oldDelegate.phase != phase ||
      oldDelegate.backdropAlpha != backdropAlpha;
}

class _GlassTourCard extends StatelessWidget {
  const _GlassTourCard({
    required this.step,
    required this.index,
    required this.total,
    required this.isLast,
    required this.ambientPhase,
    required this.onSkip,
    required this.onBack,
    required this.onNext,
  });

  final _LiveTourStep step;
  final int index;
  final int total;
  final bool isLast;
  final double ambientPhase;
  final VoidCallback onSkip;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final accent = step.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color.lerp(const Color(0xFF131926), accent, 0.14)!
                    .withValues(alpha: 0.92),
                const Color(0xFF0A0D14).withValues(alpha: 0.95),
              ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: 1.2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 34,
                spreadRadius: -4,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Barra de progreso segmentada animada
                Row(
                  children: List<Widget>.generate(total, (i) {
                    final active = i == index;
                    final done = i < index;
                    return Expanded(
                      flex: active ? 2 : 1,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        height: 4,
                        margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: active
                              ? accent
                              : done
                                  ? accent.withValues(alpha: 0.48)
                                  : Colors.white.withValues(alpha: 0.14),
                          boxShadow: active
                              ? <BoxShadow>[
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.65),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 14),

                // Encabezado: icono + eyebrow + botón Saltar
                Row(
                  children: <Widget>[
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.16),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Icon(step.icon, size: 18, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            step.eyebrow,
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.25,
                            ),
                          ),
                          Text(
                            'Paso ${index + 1} de $total',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.50),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      TextButton(
                        key: const ValueKey('live-tour-skip'),
                        onPressed: onSkip,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.65),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Omitir',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),

                Flexible(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // Emblema hero animado en la pantalla de bienvenida
                        if (step.isHeroWelcome) ...<Widget>[
                          const SizedBox(height: 18),
                          Center(
                            child: _HeroBrandEmblem(
                              accent: accent,
                              phase: ambientPhase,
                            ),
                          ),
                        ],

                        // Vista previa animada del estudio «Compartir momento»
                        if (step.showShareMomentStudioPreview) ...<Widget>[
                          const SizedBox(height: 12),
                          _ShareMomentStudioPreview(
                            accent: accent,
                            phase: ambientPhase,
                          ),
                        ],

                        const SizedBox(height: 12),

                        // Título editorial con animación suave al cambiar paso
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          child: Column(
                            key: ValueKey(step.id),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                step.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  height: 1.15,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                step.body,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.78),
                                  fontSize: 13,
                                  height: 1.42,
                                ),
                              ),
                              if (step.highlights.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: <Widget>[
                                    for (final tag in step.highlights)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          color: accent.withValues(alpha: 0.13),
                                          border: Border.all(
                                            color:
                                                accent.withValues(alpha: 0.34),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            Container(
                                              width: 5,
                                              height: 5,
                                              decoration: BoxDecoration(
                                                color: accent,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                tag,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.9),
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Controles inferiores
                Row(
                  children: <Widget>[
                    if (onBack != null) ...<Widget>[
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: OutlinedButton(
                          key: const ValueKey('live-tour-back'),
                          onPressed: onBack,
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Icon(Icons.arrow_back_rounded, size: 19),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            gradient: LinearGradient(
                              colors: <Color>[
                                accent,
                                Color.lerp(accent, Colors.white, 0.22)!,
                              ],
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: accent.withValues(alpha: 0.42),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: FilledButton(
                            key: ValueKey(
                              isLast ? 'live-tour-finish' : 'live-tour-next',
                            ),
                            onPressed: onNext,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: const Color(0xFF06100C),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Flexible(
                                  child: Text(
                                    step.nextLabel ??
                                        (step.isHeroWelcome
                                            ? 'Comenzar recorrido'
                                            : isLast
                                                ? '¡Listo, a escuchar!'
                                                : 'Siguiente'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  isLast
                                      ? Icons.check_rounded
                                      : Icons.arrow_forward_rounded,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroBrandEmblem extends StatelessWidget {
  const _HeroBrandEmblem({required this.accent, required this.phase});

  final Color accent;
  final double phase;

  @override
  Widget build(BuildContext context) {
    final breathe = 0.94 + math.sin(phase * math.pi * 2) * 0.06;
    return SizedBox(
      width: 112,
      height: 112,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Transform.scale(
            scale: breathe,
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    accent.withValues(alpha: 0.34),
                    accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Transform.rotate(
            angle: phase * math.pi * 2,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: <Color>[
                    accent.withValues(alpha: 0.05),
                    accent,
                    const Color(0xFF22D3EE),
                    accent.withValues(alpha: 0.05),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 86,
            height: 86,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF0C0F16),
            ),
            padding: const EdgeInsets.all(5),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icons/inutil_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.music_note_rounded,
                  color: accent,
                  size: 40,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini vista previa animada del estudio «Compartir momento» dentro de la
/// tarjeta Liquid Glass del paso sobre el reproductor abierto.
class _ShareMomentStudioPreview extends StatelessWidget {
  const _ShareMomentStudioPreview({
    required this.accent,
    required this.phase,
  });

  final Color accent;
  final double phase;

  @override
  Widget build(BuildContext context) {
    final slideWave = 0.5 + 0.5 * math.sin(phase * math.pi * 2);
    final windowStart = 0.12 + slideWave * 0.34;
    const windowWidth = 0.42;

    return Container(
      key: const ValueKey('share-moment-studio-preview'),
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent.withValues(alpha: 0.18),
            const Color(0xFF0E1320).withValues(alpha: 0.92),
          ],
        ),
        border: Border.all(
          color: accent.withValues(alpha: 0.36),
          width: 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          // Mini marco vertical 9:16 con ondas + letras karaoke animadas
          Container(
            width: 36,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  accent.withValues(alpha: 0.85),
                  const Color(0xFF6366F1),
                  const Color(0xFF0B0F1A),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
                width: 0.9,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                SizedBox(
                  height: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List<Widget>.generate(4, (i) {
                      final h =
                          4.0 +
                          7.0 *
                              (0.5 +
                                  0.5 *
                                      math.sin(
                                        phase * math.pi * 2 + i * 1.15,
                                      ));
                      return Container(
                        width: 3,
                        height: h,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      );
                    }),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      height: 2,
                      width: 22,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: 2,
                      width: 15,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.52),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ],
                ),
                Text(
                  '9:16',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 7,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          // Línea de recorte 5–30 s animada
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.content_cut_rounded, size: 12, color: accent),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Recorte 5–30 s · MP4',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final totalW = constraints.maxWidth;
                    final leftPx = totalW * windowStart;
                    final boxW = totalW * windowWidth;
                    return SizedBox(
                      height: 16,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: <Widget>[
                          // Pista de onda de fondo
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List<Widget>.generate(22, (i) {
                              final barH =
                                  4.0 +
                                  7.0 *
                                      (0.5 +
                                          0.5 * math.sin(i * 0.85 + 0.4));
                              return Container(
                                width: 2.2,
                                height: barH,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              );
                            }),
                          ),
                          // Ventana activa del recorte deslizándose suavemente
                          Positioned(
                            left: leftPx,
                            width: boxW,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(5),
                                color: accent.withValues(alpha: 0.24),
                                border: Border.all(
                                  color: accent,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          // Sello MP4 1080p 60 FPS
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: accent.withValues(alpha: 0.16),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '1080p',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                Text(
                  '60 FPS',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
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

/// Banner flotante *Liquid Glass* para los **Consejos Contextuales en Tiempo Real**.
/// Se monta discretamente en `HomePage` y aparece una sola vez cuando el usuario
/// descubre por primera vez pantallas clave (Buscar, Local, Biblioteca o Reproductor).
class InutixContextualCoachBanner extends StatelessWidget {
  const InutixContextualCoachBanner({
    super.key,
    required this.bottomOffset,
    required this.topAligned,
  });

  final double bottomOffset;
  final bool topAligned;

  @override
  Widget build(BuildContext context) {
    final guide = InutixLiveGuideController.instance;
    return ListenableBuilder(
      listenable: guide,
      builder: (context, _) {
        final tip = guide.activeTip;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 340),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(
              begin: Offset(0, topAligned ? -0.25 : 0.25),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: tip == null
              ? const SizedBox.shrink(key: ValueKey('no-contextual-tip'))
              : Align(
                  key: ValueKey('contextual-tip-${tip.id}'),
                  alignment: topAligned
                      ? Alignment.topCenter
                      : Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      topAligned
                          ? MediaQuery.paddingOf(context).top + 12
                          : 0,
                      14,
                      topAligned ? 0 : bottomOffset,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: <Color>[
                                  Color.lerp(
                                    const Color(0xFF141A26),
                                    tip.accent,
                                    0.16,
                                  )!
                                      .withValues(alpha: 0.92),
                                  const Color(0xFF0A0D14)
                                      .withValues(alpha: 0.95),
                                ],
                              ),
                              border: Border.all(
                                color: tip.accent.withValues(alpha: 0.48),
                                width: 1.1,
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tip.accent.withValues(alpha: 0.16),
                                    border: Border.all(
                                      color: tip.accent.withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: Icon(
                                    tip.icon,
                                    color: tip.accent,
                                    size: 19,
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        tip.badge,
                                        style: TextStyle(
                                          color: tip.accent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        tip.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        tip.body,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.78),
                                          fontSize: 12,
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: <Widget>[
                                          FilledButton(
                                            key: const ValueKey(
                                              'contextual-tip-dismiss',
                                            ),
                                            onPressed: () {
                                              HapticFeedback.selectionClick();
                                              unawaited(
                                                guide.dismissActiveTip(),
                                              );
                                            },
                                            style: FilledButton.styleFrom(
                                              backgroundColor: tip.accent,
                                              foregroundColor:
                                                  const Color(0xFF06100C),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 6,
                                              ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                            ),
                                            child: const Text(
                                              'Entendido',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          TextButton(
                                            key: const ValueKey(
                                              'contextual-tip-disable-all',
                                            ),
                                            onPressed: () {
                                              HapticFeedback.selectionClick();
                                              unawaited(
                                                guide
                                                    .disableAllContextualTips(),
                                              );
                                            },
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white
                                                  .withValues(alpha: 0.55),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 6,
                                              ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            child: const Text(
                                              'No mostrar tips',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                              ),
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
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
