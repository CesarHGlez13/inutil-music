import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/firebase/firebase_auth_service.dart';
import '../../../../core/firebase/firebase_sync_providers.dart';
import '../../../../core/theme/inutil_design_system.dart';
import 'inutil_admin_panel.dart';

/// Diálogo de gestión de cuenta Firebase para INÚTIL MUSIC.
class InutilAccountDialog extends ConsumerStatefulWidget {
  const InutilAccountDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const InutilAccountDialog(),
    );
  }

  @override
  ConsumerState<InutilAccountDialog> createState() =>
      _InutilAccountDialogState();
}

class _InutilAccountDialogState extends ConsumerState<InutilAccountDialog> {
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
      setState(() => _errorMessage = 'Por favor ingresa correo y contraseña.');
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
      if (mounted) Navigator.of(context).pop();
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
      final user = await ref.read(inutilAuthProvider).signInWithGoogle();
      if (user != null && mounted) Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(inutilAuthProvider);
    final user = auth.currentUser;

    return Dialog(
      backgroundColor: InutilDesignSystem.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: InutilDesignSystem.borderSubtle),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: user != null ? _buildUserDashboard(user) : _buildAuthForm(),
        ),
      ),
    );
  }

  Widget _buildUserDashboard(InutilUser user) {
    final auth = ref.read(inutilAuthProvider);
    final days = user.daysRemaining;
    final isExpired = user.isExpired;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: InutilDesignSystem.primaryNeon.withValues(alpha: 0.2),
              child: Text(
                user.displayName.isNotEmpty
                    ? user.displayName[0].toUpperCase()
                    : user.email[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: InutilDesignSystem.primaryNeon,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName.isNotEmpty
                        ? user.displayName
                        : 'Usuario Inútil',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: InutilDesignSystem.textPrimary,
                    ),
                  ),
                  Text(
                    user.email,
                    style: const TextStyle(
                      fontSize: 13,
                      color: InutilDesignSystem.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isExpired
                ? Colors.red.withValues(alpha: 0.12)
                : InutilDesignSystem.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isExpired
                  ? Colors.redAccent.withValues(alpha: 0.4)
                  : InutilDesignSystem.primaryNeon.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Estado de la Cuenta',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: InutilDesignSystem.textSecondary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: user.isAdmin
                          ? Colors.amber.withValues(alpha: 0.2)
                          : isExpired
                              ? Colors.red
                              : Colors.green,
                      borderRadius: BorderRadius.circular(8),
                      border: user.isAdmin
                          ? Border.all(color: Colors.amberAccent)
                          : null,
                    ),
                    child: Text(
                      user.isAdmin
                          ? '👑 ADMIN'
                          : user.isPermanent
                              ? '💎 PERMANENTE'
                              : isExpired
                                  ? 'VENCIDA'
                                  : 'ACTIVA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: user.isAdmin ? Colors.amberAccent : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                user.isAdmin
                    ? 'Acceso Supremo de Administrador (Sin límites).'
                    : user.isPermanent
                        ? 'Licencia Premium Permanente activa.'
                        : isExpired
                            ? 'Tu suscripción ha vencido. Contacta al administrador para renovarla.'
                            : 'Vigencia restante: $days días de acceso completo.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: user.isAdmin
                      ? Colors.amberAccent
                      : isExpired
                          ? Colors.redAccent
                          : Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Botón Exclusivo para César / Admin: Panel de Control
        if (user.isAdmin) ...[
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              InutilAdminPanel.show(context);
            },
            icon: const Icon(Icons.admin_panel_settings_rounded, size: 20, color: Colors.amberAccent),
            label: const Text(
              'Panel de Control de Usuarios César',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
                color: Colors.amberAccent,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.withValues(alpha: 0.15),
              side: const BorderSide(color: Colors.amberAccent, width: 1.2),
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Panel de Administración de Vencimiento
        const Text(
          'Añadir Vigencia a tu Cuenta',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: InutilDesignSystem.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => auth.adminGrantVigencia(uid: user.uid, additionalDays: 30),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
                child: const Text('+30 días'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => auth.adminGrantVigencia(uid: user.uid, additionalDays: 90),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
                child: const Text('+90 días'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => auth.adminGrantVigencia(uid: user.uid, additionalDays: 9999, isPermanent: true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amberAccent,
                  side: const BorderSide(color: Colors.amberAccent),
                ),
                child: const Text('💎 Permanente'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await auth.signOut();
                if (!mounted) return;
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Cerrar Sesión'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withValues(alpha: 0.2),
                foregroundColor: Colors.redAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAuthForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.music_note_rounded,
              color: InutilDesignSystem.primaryNeon,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              _isRegister ? 'Crear Cuenta Inútil Music' : 'Iniciar Sesión',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: InutilDesignSystem.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
        if (_isRegister) ...[
          TextField(
            controller: _displayNameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Nombre de usuario',
              labelStyle: TextStyle(color: Colors.white60),
              prefixIcon: Icon(Icons.person_outline_rounded, color: Colors.white54),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _emailController,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Correo electrónico',
            labelStyle: TextStyle(color: Colors.white60),
            prefixIcon: Icon(Icons.email_outlined, color: Colors.white54),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          style: const TextStyle(color: Colors.white),
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contraseña',
            labelStyle: TextStyle(color: Colors.white60),
            prefixIcon: Icon(Icons.lock_outline_rounded, color: Colors.white54),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: (_isLoading || _isGoogleLoading) ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: InutilDesignSystem.primaryNeon,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _isLoading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_isRegister ? 'Registrarse' : 'Iniciar Sesión'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: (_isLoading || _isGoogleLoading) ? null : _submitGoogle,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF1F1F1F),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _isGoogleLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF4285F4),
                  ),
                )
              : const Text(
                  'G   Continuar con Google',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            setState(() {
              _isRegister = !_isRegister;
              _errorMessage = null;
            });
          },
          child: Text(
            _isRegister
                ? '¿Ya tienes cuenta? Inicia sesión'
                : '¿No tienes cuenta? Regístrate',
            style: const TextStyle(color: InutilDesignSystem.accentCyan),
          ),
        ),
      ],
    );
  }
}
