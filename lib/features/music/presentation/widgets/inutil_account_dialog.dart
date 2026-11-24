import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/firebase/firebase_auth_service.dart';
import '../../../../core/firebase/firebase_sync_providers.dart';
import '../../../../core/firebase/music_qr_scanner_screen.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dialog.dart';
import '../../../../core/theme/app_ui.dart';
import '../providers/music_providers.dart';

/// Diálogo de cuenta de usuario de Inutix Music, integrado con el tema nativo
/// de la app. Sin controles administrativos (la administración vive en el
/// portal web).
class InutilAccountDialog extends ConsumerStatefulWidget {
  const InutilAccountDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showAppDialog<void>(
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
  bool _signingOut = false;
  bool _cloudBusy = false;
  String? _cloudMessage;
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
      setState(() => _errorMessage = 'Ingresa tu correo y contraseña.');
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
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
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
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      // Detener inmediatamente la reproducción y vaciar la cola nativa antes
      // de cerrar sesión para que la música no continúe sonando ni se pueda
      // controlar desde la notificación o pantalla de bloqueo.
      try {
        await ref.read(playerControllerProvider.notifier).stop();
      } catch (_) {}
      await ref.read(inutilAuthProvider).signOut();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(inutilAuthProvider);
    final user = auth.currentUser;

    return AppAlertDialog(
      scrollable: true,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: user != null
            ? _buildUserProfile(context, user)
            : _buildAuthForm(context),
      ),
    );
  }

  Widget _buildUserProfile(BuildContext context, InutilUser user) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final days = user.daysRemaining;
    final isExpired = !user.isAdmin && user.isExpired;
    final isPermanent = user.isAdmin || user.isPermanent;

    final statusColor = isExpired ? colors.error : colors.primary;
    final statusLabel = isExpired
        ? 'Vencida'
        : isPermanent
        ? 'Activa'
        : 'Activa · $days d';
    final statusMessage = isExpired
        ? 'Tu acceso ha vencido. Solicita una renovación para continuar.'
        : isPermanent
        ? 'Acceso completo activo sin límite de fecha.'
        : 'Vigencia restante: $days días de acceso completo.';

    final displayName = user.displayName.trim().isNotEmpty
        ? user.displayName.trim()
        : user.email.split('@').first;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: colors.primaryContainer,
              foregroundColor: colors.onPrimaryContainer,
              child: Text(
                initial,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardSurfaceFor(context),
            borderRadius: BorderRadius.circular(appCardRadius),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Estado de la cuenta',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                statusMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isExpired ? colors.error : colors.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardSurfaceFor(context),
            borderRadius: BorderRadius.circular(appCardRadius),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Respaldo en la nube',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _cloudMessage ??
                    'Tus playlists y biblioteca se sincronizan automáticamente con tu cuenta.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('account-restore-backup'),
                    onPressed: _cloudBusy || _signingOut
                        ? null
                        : _restoreCloudBackup,
                    icon: const Icon(Icons.cloud_download_rounded, size: 18),
                    label: const Text('Restaurar listas'),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('account-push-backup'),
                    onPressed: _cloudBusy || _signingOut
                        ? null
                        : _pushCloudBackup,
                    icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: const Text('Respaldar ahora'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardSurfaceFor(context),
            borderRadius: BorderRadius.circular(appCardRadius),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Iniciar sesión en PC',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Abre Inutix Music en tu computadora y escanea el QR (o escribe su código) para entrar sin contraseña.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('account-pc-login-qr'),
                    onPressed: _signingOut
                        ? null
                        : () => openPcLoginFlow(context),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Escanear QR de la PC'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('account-pc-login-code'),
                    onPressed: _signingOut
                        ? null
                        : () => showPcLoginCodeDialog(context),
                    icon: const Icon(Icons.keyboard_rounded, size: 18),
                    label: const Text('Escribir código'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _signingOut ? null : () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              key: const ValueKey('account-sign-out'),
              onPressed: _signingOut ? null : _signOut,
              style: FilledButton.styleFrom(
                backgroundColor: colors.errorContainer,
                foregroundColor: colors.onErrorContainer,
              ),
              icon: _signingOut
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onErrorContainer,
                      ),
                    )
                  : const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Cerrar sesión'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _restoreCloudBackup() async {
    setState(() {
      _cloudBusy = true;
      _cloudMessage = 'Buscando respaldo en la nube…';
    });
    try {
      final backup = ref.read(inutilCloudBackupProvider);
      final message = await backup.pullAndRestoreIfEmpty();
      if (backup.lastRestoreHadChanges) {
        ref
          ..invalidate(libraryTracksProvider)
          ..invalidate(playlistsControllerProvider)
          ..invalidate(catalogPlaylistsProvider)
          ..invalidate(catalogPlaylistProvider)
          ..invalidate(favoriteTrackIdsProvider)
          ..invalidate(historyProvider);
      }
      if (mounted) {
        setState(() => _cloudMessage = message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cloudMessage = 'No se pudo restaurar: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _cloudBusy = false);
      }
    }
  }

  Future<void> _pushCloudBackup() async {
    setState(() {
      _cloudBusy = true;
      _cloudMessage = 'Respaldando playlists en la nube…';
    });
    try {
      final backup = ref.read(inutilCloudBackupProvider);
      await backup.pushNow();
      if (mounted) {
        setState(
          () => _cloudMessage = backup.lastError.isEmpty
              ? 'Respaldo completado correctamente.'
              : backup.lastError,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cloudMessage = 'No se pudo respaldar: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _cloudBusy = false);
      }
    }
  }

  Widget _buildAuthForm(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isRegister ? 'Crear cuenta' : 'Iniciar sesión',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _isRegister
              ? 'Sincroniza tus playlists y dispositivos en la nube.'
              : 'Accede a tu biblioteca y configuración en la nube.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        if (_isRegister) ...[
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              labelText: 'Nombre o alias',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Correo electrónico',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: (_isLoading || _isGoogleLoading) ? null : _submit,
          child: _isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isRegister ? 'Registrarse' : 'Entrar'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: (_isLoading || _isGoogleLoading) ? null : _submitGoogle,
          icon: _isGoogleLoading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.g_mobiledata_rounded, size: 22),
          label: const Text('Continuar con Google'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _isRegister = !_isRegister;
            _errorMessage = null;
          }),
          child: Text(
            _isRegister
                ? '¿Ya tienes cuenta? Inicia sesión'
                : '¿No tienes cuenta? Regístrate',
          ),
        ),
      ],
    );
  }
}
