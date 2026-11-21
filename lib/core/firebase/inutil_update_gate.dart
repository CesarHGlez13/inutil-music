import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'inutil_update_service.dart';

/// Puerta del kill switch de actualizaciones (OTA forzosa).
///
/// INÚTIL MUSIC publica su versión en `app_config/release` (o `release.json`),
/// y el administrador puede fijar ahí un `minSupportedVersion`. Cuando la
/// versión instalada queda por debajo de ese mínimo —o el manifiesto marca la
/// actualización como obligatoria— esta puerta reemplaza TODA la interfaz por
/// [InutilForceUpdateScreen]: la versión antigua deja de ser utilizable, se
/// muestra el letrero y la única salida es descargar e instalar desde la misma
/// app. No se puede descartar ni volver atrás con el botón del sistema.
///
/// Cuando hay una versión superior que NO es obligatoria la puerta no cambia
/// la interfaz: muestra el mismo diálogo de novedades ([showInutilUpdateDialog])
/// como aviso descartable una sola vez por versión publicada. La versión que el
/// usuario pospuso queda recordada en prefs, así que el cartel no vuelve a
/// aparecer en los siguientes arranques hasta que se publique algo más nuevo.
///
/// Sin red (o cuando el manifiesto no responde) [InutilUpdateService] devuelve
/// la última versión conocida o "estás al día", así que la app nunca se
/// autobloquea por un corte de conexión.
class InutilUpdateGate extends ConsumerStatefulWidget {
  const InutilUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InutilUpdateGate> createState() => _InutilUpdateGateState();
}

class _InutilUpdateGateState extends ConsumerState<InutilUpdateGate>
    with WidgetsBindingObserver {
  /// Revalidación mínima al volver a primer plano: el admin puede publicar el
  /// kill switch mientras la app estaba en segundo plano.
  static const Duration _resumeCooldown = Duration(minutes: 5);

  /// Versión que el usuario pospuso desde el aviso no bloqueante. Se guarda en
  /// prefs para que el mismo cartel no reaparezca en cada arranque; cualquier
  /// manifiesto con una versión distinta lo vuelve a activar.
  static const String _snoozePrefKey = 'inutil_update_notice_snoozed_for';

  InutilReleaseInfo? _blocker;
  bool _checking = false;
  DateTime? _lastCheck;
  bool _noticeInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // El arranque no se bloquea: la UI monta primero y el manifiesto se
    // consulta en paralelo; si resulta obsoleto, el árbol se cambia en cuanto
    // responde (normalmente antes de que el usuario termine de navegar).
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    if (last != null && DateTime.now().difference(last) < _resumeCooldown) {
      return;
    }
    unawaited(_check());
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    InutilReleaseInfo? release;
    try {
      release = await InutilUpdateService.instance.checkForUpdate();
    } catch (e) {
      debugPrint('Chequeo OTA del kill switch falló: $e');
    } finally {
      _checking = false;
      _lastCheck = DateTime.now();
    }
    if (!mounted || release == null) return;
    final forced =
        release.belowMinSupported ||
        (release.updateAvailable && release.effectiveMandatory);
    setState(() => _blocker = forced ? release : null);
    if (forced || !release.updateAvailable) return;
    // El aviso opcional no bloquea nada: la app sigue usable y el usuario
    // decide si actualiza ahora o lo pospone.
    if (await _snoozedVersion() == release.latestVersion) return;
    if (!mounted) return;
    await _showNotice(release);
  }

  /// Diálogo descartable de novedades ([showInutilUpdateDialog]) para una
  /// actualización opcional. Al cerrarse —sea por el botón, el botón físico o
  /// tocando fuera— se recuerda la versión pospuesta en prefs, de modo que el
  /// mismo aviso no vuelva a salir hasta que se publique una versión superior.
  Future<void> _showNotice(InutilReleaseInfo release) async {
    if (_noticeInFlight || !context.mounted) return;
    _noticeInFlight = true;
    try {
      await showInutilUpdateDialog(context, release);
      await _rememberSnoozedVersion(release.latestVersion);
    } catch (e) {
      debugPrint('Aviso OTA no bloqueante falló: $e');
    } finally {
      _noticeInFlight = false;
    }
  }

  /// Última versión pospuesta desde el aviso, o cadena vacía si nunca se pospuso.
  Future<String> _snoozedVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString(_snoozePrefKey) ?? '').trim();
    } catch (_) {
      // Sin prefs (plataforma de prueba o fallo de canal): se muestra el aviso.
      return '';
    }
  }

  Future<void> _rememberSnoozedVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_snoozePrefKey, version.trim());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final blocker = _blocker;
    if (blocker == null) return widget.child;
    return PopScope(
      canPop: false,
      // Atrapa también el "atrás" del sistema en Android antes de que salga
      // de la app: la versión inservible no ofrece otra pantalla.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && blocker.belowMinSupported) {
          debugPrint(
            'Bloqueado por kill switch: v${blocker.currentVersion} '
            'requiere v${blocker.latestVersion}.',
          );
        }
      },
      child: InutilForceUpdateScreen(release: blocker, onRetry: _check),
    );
  }
}

/// Letrero de actualización obligatoria a pantalla completa.
///
/// Reutiliza [InutilUpdateDialogContent] (la misma tarjeta con novedades,
/// progreso y botón de descarga del diálogo manual de Ajustes) para que el
/// usuario actualice sin salir de la app.
class InutilForceUpdateScreen extends StatelessWidget {
  const InutilForceUpdateScreen({
    super.key,
    required this.release,
    this.onRetry,
  });

  final InutilReleaseInfo release;

  /// Vuelve a consultar el manifiesto (útil si el admin ya publicó una
  /// versión superior o si la descarga se hizo en otro dispositivo).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      release.belowMinSupported
                          ? 'ACTUALIZACIÓN REQUERIDA'
                          : 'ACTUALIZACIÓN DISPONIBLE',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: release.belowMinSupported
                            ? colors.error
                            : colors.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    InutilUpdateDialogContent(release: release),
                    if (onRetry != null) ...[
                      const SizedBox(height: 14),
                      TextButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Comprobar de nuevo'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
