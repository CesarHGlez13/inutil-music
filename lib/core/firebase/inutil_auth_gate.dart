import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/music/presentation/providers/music_providers.dart';
import '../theme/inutil_design_system.dart';
import 'firebase_auth_service.dart';
import 'firebase_sync_providers.dart';
import 'inutil_inactivity_paused_screen.dart';
import 'music_qr_login_panel.dart';

/// Barrera de autenticación obligatoria (Gatekeeper) para INÚTIL MUSIC.
/// Bloquea el uso de la aplicación a usuarios no registrados o sin licencia activa
/// y detiene inmediatamente cualquier reproducción activa si se cierra la sesión.
class InutilAuthGate extends ConsumerStatefulWidget {
  const InutilAuthGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InutilAuthGate> createState() => _InutilAuthGateState();
}

class _InutilAuthGateState extends ConsumerState<InutilAuthGate> {
  bool _wasAllowed = false;

  void _stopPlaybackSafely() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        unawaited(ref.read(playerControllerProvider.notifier).stop());
      } catch (_) {
        // Isolated widget tests may mount InutilAuthGate without player providers.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(inutilAuthProvider);
    final user = auth.currentUser;
    final allowed =
        user != null &&
        !auth.isKickedOut &&
        !auth.isInactivityPaused &&
        (user.isAdmin || (user.isActive && !user.isExpired));

    if (!allowed && _wasAllowed) {
      _stopPlaybackSafely();
    }
    _wasAllowed = allowed;

    // 1. Si no hay usuario autenticado -> Obligatorio Iniciar Sesión / Registrarse
    if (user == null) {
      return const InutilAuthScreen();
    }

    // 2. Sesión expulsada (otro teléfono tomó el control, cuenta borrada o
    //    bloqueada mientras se usaba la app): se muestra el motivo.
    if (auth.isKickedOut) {
      return InutilLicenseExpiredScreen(
        user: user,
        reason: auth.kickedOutReason,
      );
    }

    // 3. Si el usuario está registrado pero está inactivo o vencido y NO es admin
    if (!user.isAdmin && (!user.isActive || user.isExpired)) {
      return InutilLicenseExpiredScreen(user: user);
    }

    // 4. Cuenta gratuita en pausa automática por inactividad.
    if (auth.isInactivityPaused) {
      return InutilInactivityPausedScreen(
        user: user,
        inactiveDays: auth.inactiveDays,
        policyDays: auth.inactivityPolicyDays,
        onSignOut: () async {
          try {
            await ref.read(playerControllerProvider.notifier).stop();
          } catch (_) {}
          await InutilAuthService.instance.signOut();
        },
      );
    }

    // 5. Acceso autorizado: Administrador o usuario con licencia activa
    return widget.child;
  }
}

/// Pantalla completa de Autenticación Obligatoria (Login / Registro)
class InutilAuthScreen extends ConsumerStatefulWidget {
  const InutilAuthScreen({super.key});

  @override
  ConsumerState<InutilAuthScreen> createState() => _InutilAuthScreenState();
}

class _InutilAuthScreenState extends ConsumerState<InutilAuthScreen> {
  bool _isRegister = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _errorMessage;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = ref.read(inutilAuthProvider);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(
        () => _errorMessage = 'Por favor ingresa tu correo y contraseña.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isRegister) {
        await auth.register(
          email: email,
          password: password,
          displayName: _displayNameController.text.trim(),
        );
      } else {
        await auth.signIn(email: email, password: password);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
    });
    try {
      await ref.read(inutilAuthProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController(text: _emailController.text);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: InutilDesignSystem.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: InutilDesignSystem.borderSubtle),
        ),
        title: const Text(
          'Recuperar Contraseña',
          style: TextStyle(
            color: InutilDesignSystem.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa tu correo registrado para recibir un enlace de restablecimiento:',
              style: TextStyle(
                color: InutilDesignSystem.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo Electrónico',
                labelStyle: TextStyle(color: Colors.white60),
                prefixIcon: Icon(Icons.email_outlined, color: Colors.white54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isNotEmpty) {
                await ref.read(inutilAuthProvider).sendPasswordReset(email);
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Enlace enviado a $email si está registrado.',
                      ),
                      backgroundColor: InutilDesignSystem.primaryNeon,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: InutilDesignSystem.primaryNeon,
              foregroundColor: Colors.white,
            ),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: InutilDesignSystem.surfaceDark,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            // Fondo ambiental con glow dinámico
            Positioned(
              top: -120,
              left: -120,
              child: IgnorePointer(
                child: Container(
                  width: 380,
                  height: 380,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        InutilDesignSystem.primaryNeon.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              right: -100,
              child: IgnorePointer(
                child: Container(
                  width: 350,
                  height: 350,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        InutilDesignSystem.accentCyan.withValues(alpha: 0.14),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Contenido centrado
            Positioned.fill(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 40,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 36,
                    runSpacing: 28,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isDesktop ? 460 : 400,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logotipo e Identidad de Marca
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: InutilDesignSystem.surfaceElevated,
                                border: Border.all(
                                  color: InutilDesignSystem.primaryNeon
                                      .withValues(alpha: 0.4),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: InutilDesignSystem.primaryNeon
                                        .withValues(alpha: 0.3),
                                    blurRadius: 24,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/icons/inutil_icon.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.album_rounded,
                                    size: 44,
                                    color: InutilDesignSystem.primaryNeon,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'INÚTIL MUSIC',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.2,
                                color: InutilDesignSystem.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Plataforma de Audio & Streaming de Alta Calidad',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: InutilDesignSystem.textSecondary,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Tarjeta de Formulario Glassmorphism
                            Container(
                              padding: const EdgeInsets.all(26),
                              decoration: BoxDecoration(
                                color: InutilDesignSystem.surfaceElevated
                                    .withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: InutilDesignSystem.borderSubtle,
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    blurRadius: 30,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Selector de pestaña (Login / Registro)
                                  Container(
                                    height: 44,
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: InutilDesignSystem.surfaceDark,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => setState(() {
                                              _isRegister = false;
                                              _errorMessage = null;
                                            }),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: !_isRegister
                                                    ? InutilDesignSystem
                                                          .primaryNeon
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                'Iniciar Sesión',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: !_isRegister
                                                      ? Colors.white
                                                      : InutilDesignSystem
                                                            .textSecondary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => setState(() {
                                              _isRegister = true;
                                              _errorMessage = null;
                                            }),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: _isRegister
                                                    ? InutilDesignSystem
                                                          .primaryNeon
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                'Crear Cuenta',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: _isRegister
                                                      ? Colors.white
                                                      : InutilDesignSystem
                                                            .textSecondary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 22),

                                  // Banner de error si existe
                                  if (_errorMessage != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.redAccent.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.error_outline_rounded,
                                            color: Colors.redAccent,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _errorMessage!,
                                              style: const TextStyle(
                                                color: Colors.redAccent,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],

                                  // Campo de Nombre en modo Registro
                                  if (_isRegister) ...[
                                    TextField(
                                      controller: _displayNameController,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Tu Nombre o Alias',
                                        labelStyle: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 13,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.person_outline_rounded,
                                          color: Colors.white54,
                                          size: 20,
                                        ),
                                        filled: true,
                                        fillColor:
                                            InutilDesignSystem.surfaceDark,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                  ],

                                  // Campo Correo Electrónico
                                  TextField(
                                    controller: _emailController,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: InputDecoration(
                                      labelText: 'Correo Electrónico',
                                      labelStyle: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 13,
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.email_outlined,
                                        color: Colors.white54,
                                        size: 20,
                                      ),
                                      filled: true,
                                      fillColor: InutilDesignSystem.surfaceDark,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),

                                  // Campo Contraseña
                                  TextField(
                                    controller: _passwordController,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    obscureText: true,
                                    decoration: InputDecoration(
                                      labelText: 'Contraseña',
                                      labelStyle: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 13,
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                        color: Colors.white54,
                                        size: 20,
                                      ),
                                      filled: true,
                                      fillColor: InutilDesignSystem.surfaceDark,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  if (!_isRegister)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: _showForgotPasswordDialog,
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text(
                                          '¿Olvidaste tu contraseña?',
                                          style: TextStyle(
                                            color:
                                                InutilDesignSystem.accentCyan,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 20),

                                  // Botón Principal de Envío
                                  ElevatedButton(
                                    onPressed: (_isLoading || _isGoogleLoading)
                                        ? null
                                        : _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          InutilDesignSystem.primaryNeon,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 4,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox.square(
                                            dimension: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            _isRegister
                                                ? 'Crear Cuenta y Empezar'
                                                : 'Acceder a Inútil Music',
                                            style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(height: 14),

                                  // Separador
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Divider(
                                          color: Colors.white.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Text(
                                          'o continúa con',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.5,
                                            ),
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Divider(
                                          color: Colors.white.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // Botón Continuar con Google
                                  SizedBox(
                                    height: 46,
                                    child: OutlinedButton(
                                      onPressed:
                                          (_isLoading || _isGoogleLoading)
                                          ? null
                                          : _submitGoogle,
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: const Color(
                                          0xFF1F1F1F,
                                        ),
                                        side: BorderSide(
                                          color: Colors.white.withValues(
                                            alpha: 0.2,
                                          ),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: _isGoogleLoading
                                          ? const SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.4,
                                                color: Color(0xFF4285F4),
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Container(
                                                  width: 22,
                                                  height: 22,
                                                  alignment: Alignment.center,
                                                  decoration:
                                                      const BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: Color(
                                                          0xFFF1F3F4,
                                                        ),
                                                      ),
                                                  child: const Text(
                                                    'G',
                                                    style: TextStyle(
                                                      color: Color(0xFF4285F4),
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                const Text(
                                                  'Continuar con Google',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.2,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Aviso legal e informativo
                            const Text(
                              'Se requiere cuenta activa con vigencia concedida por el Administrador para disfrutar del servicio completo.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: InutilDesignSystem.textMuted,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Inicio de sesión por QR desde el celular (solo escritorio).
                      if (MusicQrLoginPanel.isSupportedPlatform)
                        const MusicQrLoginPanel(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pantalla mostrada cuando la cuenta está inactiva o su vigencia ha expirado
class InutilLicenseExpiredScreen extends ConsumerStatefulWidget {
  const InutilLicenseExpiredScreen({
    super.key,
    required this.user,
    this.reason,
  });

  final InutilUser user;

  /// Motivo específico de bloqueo (sesión expulsada por otro teléfono, límite
  /// de cambios mensuales, cuenta eliminada...). Si es nulo se decide según el
  /// estado de la licencia.
  final String? reason;

  @override
  ConsumerState<InutilLicenseExpiredScreen> createState() =>
      _InutilLicenseExpiredScreenState();
}

class _InutilLicenseExpiredScreenState
    extends ConsumerState<InutilLicenseExpiredScreen> {
  bool _isChecking = false;

  Future<void> _checkStatus() async {
    setState(() => _isChecking = true);
    await InutilAuthService.instance.refreshCurrentUserProfile();
    if (mounted) {
      setState(() => _isChecking = false);
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Sin fecha registrada';
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final isSuspended = !user.isActive && user.status != 'pending';
    final isPending = user.status == 'pending' && !user.isAdmin;
    final reason = widget.reason;

    final String title;
    final String message;
    if (reason != null && reason.isNotEmpty) {
      title = 'SESIÓN BLOQUEADA';
      message = reason;
    } else if (isPending) {
      title = 'CUENTA PENDIENTE';
      message =
          'Tu cuenta ya está registrada, pero el Administrador aún no te ha '
          'concedido vigencia. En cuanto la active podrás reproducir.';
    } else if (isSuspended) {
      title = 'CUENTA SUSPENDIDA';
      message =
          'Tu cuenta ha sido desactivada temporalmente por el Administrador.';
    } else {
      title = 'LICENCIA VENCIDA';
      message =
          'Tu periodo de vigencia en Inútil Music ha caducado. Es necesario '
          'que el Administrador renueve tu licencia para continuar escuchando '
          'música.';
    }

    return Scaffold(
      backgroundColor: InutilDesignSystem.surfaceDark,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ícono de Bloqueo con glow
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.withValues(alpha: 0.15),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.5),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent.withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.lock_clock_rounded,
                    size: 46,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 10),

                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: InutilDesignSystem.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),

                // Tarjeta de información del usuario
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: InutilDesignSystem.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: InutilDesignSystem.borderSubtle),
                  ),
                  child: Column(
                    children: [
                      _buildInfoRow(
                        'Usuario',
                        user.displayName.isNotEmpty
                            ? user.displayName
                            : user.email.split('@').first,
                      ),
                      const Divider(color: Colors.white12, height: 20),
                      _buildInfoRow('Correo', user.email),
                      const Divider(color: Colors.white12, height: 20),
                      _buildInfoRow('ID Cuenta', user.uid),
                      const Divider(color: Colors.white12, height: 20),
                      _buildInfoRow(
                        'Vencimiento',
                        _formatDate(user.accountExpiresAt),
                      ),
                      const Divider(color: Colors.white12, height: 20),
                      _buildInfoRow(
                        'Estado',
                        reason != null && reason.isNotEmpty
                            ? 'Sesión bloqueada'
                            : isPending
                            ? 'Pendiente de aprobación'
                            : isSuspended
                            ? 'Suspendida'
                            : 'Expirada',
                        color: Colors.redAccent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Botones de acción
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isChecking ? null : _checkStatus,
                        icon: _isChecking
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Comprobar Estado'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: InutilDesignSystem.primaryNeon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await ref.read(playerControllerProvider.notifier).stop();
                    } catch (_) {}
                    await InutilAuthService.instance.signOut();
                  },
                  icon: const Icon(
                    Icons.logout_rounded,
                    size: 16,
                    color: Colors.white70,
                  ),
                  label: const Text(
                    'Cerrar Sesión e Ingresar con otra Cuenta',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Nota de contacto
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.amberAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.amberAccent,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ponte en contacto con César (Administrador) proporcionando tu correo o ID para activar tu licencia de acceso.',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 12,
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

  Widget _buildInfoRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: InutilDesignSystem.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color ?? InutilDesignSystem.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
