import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import '../theme/inutil_design_system.dart';
import '../theme/inutil_icons.dart';
import 'firebase_auth_service.dart';

/// Pantalla amigable que aparece cuando una cuenta gratuita quedó en pausa
/// automática por no usar la app durante [policyDays] días.
///
/// No es un castigo: deja claro que la biblioteca sigue segura en la nube y
/// ofrece tres salidas (pedir reactivación, comprobar estado o apoyar al
/// creador para obtener acceso permanente).
class InutilInactivityPausedScreen extends StatefulWidget {
  const InutilInactivityPausedScreen({
    required this.user,
    required this.inactiveDays,
    required this.policyDays,
    this.onRequestReactivation,
    this.onCheckStatus,
    this.onSignOut,
    super.key,
  });

  final InutilUser user;
  final int inactiveDays;
  final int policyDays;

  /// Inyectables para pruebas; por defecto usan [InutilAuthService].
  final Future<bool> Function()? onRequestReactivation;
  final Future<void> Function()? onCheckStatus;
  final Future<void> Function()? onSignOut;

  @override
  State<InutilInactivityPausedScreen> createState() =>
      _InutilInactivityPausedScreenState();
}

class _InutilInactivityPausedScreenState
    extends State<InutilInactivityPausedScreen>
    with SingleTickerProviderStateMixin {
  static const Color _accent = Color(0xFF8B9CFF);

  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  bool _requesting = false;
  bool _requested = false;
  bool _checking = false;
  String? _feedback;

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  Future<void> _requestReactivation() async {
    setState(() {
      _requesting = true;
      _feedback = null;
    });
    final ok =
        await (widget.onRequestReactivation ??
            InutilAuthService.instance.requestReactivation)();
    if (!mounted) return;
    setState(() {
      _requesting = false;
      _requested = ok;
      _feedback = ok
          ? 'Solicitud enviada. Te avisaremos en cuanto el creador la apruebe.'
          : 'No pudimos enviar la solicitud. Revisa tu conexión e inténtalo de nuevo.';
    });
  }

  Future<void> _checkStatus() async {
    setState(() {
      _checking = true;
      _feedback = null;
    });
    await (widget.onCheckStatus ??
        InutilAuthService.instance.refreshCurrentUserProfile)();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (InutilAuthService.instance.isInactivityPaused) {
        _feedback = 'Tu acceso sigue en pausa por ahora.';
      }
    });
  }

  Future<void> _support() async {
    try {
      await launchUrl(
        Uri.parse(AppConstants.supportDevelopmentUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.user.displayName.trim().isNotEmpty
        ? widget.user.displayName.trim().split(' ').first
        : widget.user.email.split('@').first;

    return Scaffold(
      key: const ValueKey('inutil-inactivity-paused-screen'),
      backgroundColor: InutilDesignSystem.surfaceDark,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12142A), InutilDesignSystem.surfaceDark],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: AnimatedBuilder(
                        animation: _breath,
                        builder: (_, child) {
                          final t = Curves.easeInOut.transform(_breath.value);
                          return Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _accent.withValues(alpha: 0.12),
                              border: Border.all(
                                color: _accent.withValues(alpha: 0.45),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _accent.withValues(
                                    alpha: 0.18 + 0.18 * t,
                                  ),
                                  blurRadius: 22 + 18 * t,
                                  spreadRadius: 2 + 4 * t,
                                ),
                              ],
                            ),
                            child: child,
                          );
                        },
                        child: const Center(
                          child: InutilIcon(
                            InutilGlyph.sleepTimer,
                            size: 44,
                            color: _accent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      'Tu acceso gratuito\nestá en pausa, $name',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: InutilDesignSystem.textPrimary,
                        fontSize: 25,
                        height: 1.18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No detectamos actividad durante ${widget.inactiveDays} '
                      'días (el límite es ${widget.policyDays}). Para mantener '
                      'los cupos gratuitos disponibles para quienes escuchan a '
                      'diario, tu acceso se pausó automáticamente.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: InutilDesignSystem.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: InutilDesignSystem.surfaceElevated,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: InutilDesignSystem.borderSubtle,
                        ),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TU MÚSICA SIGUE A SALVO',
                            style: TextStyle(
                              color: Color(0xFF34D399),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 12),
                          _SafeRow(
                            glyph: InutilGlyph.library,
                            text:
                                'Playlists y Favoritos respaldados en la nube',
                          ),
                          SizedBox(height: 10),
                          _SafeRow(
                            glyph: InutilGlyph.sparkles,
                            text: 'Tu Resumen del Año y estadísticas intactas',
                          ),
                          SizedBox(height: 10),
                          _SafeRow(
                            glyph: InutilGlyph.settings,
                            text: 'Tus ajustes te esperan tal como los dejaste',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      key: const ValueKey('inactivity-request-reactivation'),
                      onPressed: _requesting || _requested
                          ? null
                          : _requestReactivation,
                      icon: _requesting
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _requested
                                  ? Icons.check_circle_rounded
                                  : Icons.waving_hand_rounded,
                              size: 18,
                            ),
                      label: Text(
                        _requested
                            ? 'Solicitud enviada'
                            : 'Solicitar reactivación',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: InutilDesignSystem.primaryNeon,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: InutilDesignSystem.primaryNeon
                            .withValues(alpha: 0.35),
                        disabledForegroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const ValueKey('inactivity-check-status'),
                      onPressed: _checking ? null : _checkStatus,
                      icon: _checking
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Comprobar estado'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: InutilDesignSystem.textPrimary,
                        side: const BorderSide(
                          color: InutilDesignSystem.borderHighlight,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      key: const ValueKey('inactivity-support-creator'),
                      onPressed: _support,
                      icon: const Text('💛', style: TextStyle(fontSize: 16)),
                      label: const Text(
                        'Apoya al creador y obtén acceso permanente',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFBBF24),
                      ),
                    ),
                    if (_feedback != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _feedback!,
                        key: const ValueKey('inactivity-feedback'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: InutilDesignSystem.textSecondary,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () async {
                        await (widget.onSignOut ??
                            InutilAuthService.instance.signOut)();
                      },
                      child: const Text(
                        'Cerrar sesión',
                        style: TextStyle(
                          color: InutilDesignSystem.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
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

class _SafeRow extends StatelessWidget {
  const _SafeRow({required this.glyph, required this.text});

  final InutilGlyph glyph;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InutilIcon(glyph, size: 18, color: const Color(0xFF34D399)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: InutilDesignSystem.textPrimary,
              fontSize: 13.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
