import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/firebase/firebase_auth_service.dart';
import '../../../../core/firebase/firebase_sync_providers.dart';
import '../../../../core/firebase/inutil_update_service.dart';
import '../../../../core/theme/inutil_design_system.dart';

/// Panel integral de Administración de Usuarios y Licencias para César.
class InutilAdminPanel extends ConsumerStatefulWidget {
  const InutilAdminPanel({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (context) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 20),
        child: InutilAdminPanel(),
      ),
    );
  }

  @override
  ConsumerState<InutilAdminPanel> createState() => _InutilAdminPanelState();
}

class _InutilAdminPanelState extends ConsumerState<InutilAdminPanel> {
  List<InutilUser> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'todos'; // todos, activos, vencidos, admins

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final auth = ref.read(inutilAuthProvider);
    final list = await auth.getAllUsers();
    if (mounted) {
      setState(() {
        _users = list;
        _isLoading = false;
      });
    }
  }

  List<InutilUser> get _filteredUsers {
    return _users.where((u) {
      // 1. Filtro de búsqueda
      final query = _searchQuery.trim().toLowerCase();
      final matchSearch =
          query.isEmpty ||
          u.email.toLowerCase().contains(query) ||
          u.displayName.toLowerCase().contains(query) ||
          u.uid.toLowerCase().contains(query);

      if (!matchSearch) return false;

      // 2. Filtro de estado
      switch (_selectedFilter) {
        case 'activos':
          return u.isActive && !u.isExpired;
        case 'vencidos':
          return u.isExpired || !u.isActive;
        case 'pendientes':
          return u.status == 'pending';
        case 'admins':
          return u.isAdmin;
        default:
          return true;
      }
    }).toList();
  }

  /// Registros que esperan que el admin les conceda vigencia: sin aprobación
  /// no pueden reproducir nada (la regla la impone Firestore, no la app).
  int get _pendingCount => _users.where((u) => u.status == 'pending').length;

  /// Aprobar un registro nuevo: concede vigencia y lo deja en `active`.
  Future<void> _approvePending(InutilUser user) async {
    await _grantVigencia(user.uid, 30, email: user.email);
  }

  /// Libera el teléfono registrado en la cuenta, para que el usuario pueda
  /// reclamarlo desde otro dispositivo sin esperar al límite mensual.
  Future<void> _releaseDevice(String uid, String email) async {
    final auth = ref.read(inutilAuthProvider);
    await auth.adminRevokeDevice(uid);
    await _loadUsers();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Dispositivo de $email liberado: ya puede tomarlo otro teléfono.',
          ),
          backgroundColor: InutilDesignSystem.accentCyan,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Sin fecha';
    if (dt.year >= 2090) return 'Licencia Permanente';
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    return '$day/$month/$year';
  }

  Future<void> _grantVigencia(
    String uid,
    int days, {
    bool isPermanent = false,
    String? email,
  }) async {
    final auth = ref.read(inutilAuthProvider);
    await auth.adminGrantVigencia(
      uid: uid,
      additionalDays: days,
      isPermanent: isPermanent,
    );
    await _loadUsers();
    if (mounted) {
      final msg = isPermanent
          ? '💎 Licencia Premium Permanente concedida a $email'
          : '+$days días de vigencia otorgados a $email';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: InutilDesignSystem.primaryNeon,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickCustomDate(
    String uid,
    String email,
    DateTime? currentDate,
  ) async {
    final now = DateTime.now();
    final initialDate = (currentDate != null && currentDate.isAfter(now))
        ? currentDate
        : now.add(const Duration(days: 30));

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: DateTime(2099, 12, 31),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: InutilDesignSystem.primaryNeon,
              surface: InutilDesignSystem.surfaceElevated,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked != null) {
      final auth = ref.read(inutilAuthProvider);
      await auth.adminSetExactExpiration(uid: uid, newExpiry: picked);
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Vencimiento de $email fijado al ${_formatDate(picked)}',
            ),
            backgroundColor: InutilDesignSystem.primaryNeon,
          ),
        );
      }
    }
  }

  Future<void> _toggleActive(
    String uid,
    bool currentActive,
    String email,
  ) async {
    final auth = ref.read(inutilAuthProvider);
    await auth.adminToggleUserActive(uid: uid, isActive: !currentActive);
    await _loadUsers();
    if (mounted) {
      final status = !currentActive ? 'Activada' : 'Suspendida';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cuenta de $email: $status'),
          backgroundColor: !currentActive ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  Future<void> _toggleRole(String uid, String currentRole, String email) async {
    final auth = ref.read(inutilAuthProvider);
    final newRole = currentRole == 'admin' ? 'user' : 'admin';
    await auth.adminToggleUserRole(uid: uid, role: newRole);
    await _loadUsers();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rol de $email actualizado a: $newRole'),
          backgroundColor: newRole == 'admin' ? Colors.amber : Colors.blue,
        ),
      );
    }
  }

  Future<void> _deleteUserConfirm(String uid, String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: InutilDesignSystem.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '¿Eliminar Usuario?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar permanentemente la cuenta de $email?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final auth = ref.read(inutilAuthProvider);
      await auth.adminDeleteUser(uid);
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Usuario $email eliminado.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _showCreateUserDialog() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController(text: 'inutil123');
    final nameController = TextEditingController();
    int initialDays = 30;
    bool isPermanent = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: InutilDesignSystem.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: InutilDesignSystem.borderSubtle),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.person_add_rounded,
                color: InutilDesignSystem.primaryNeon,
              ),
              SizedBox(width: 10),
              Text(
                'Registrar Nuevo Usuario',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Correo Electrónico',
                    labelStyle: TextStyle(color: Colors.white60),
                    prefixIcon: Icon(
                      Icons.email_outlined,
                      color: Colors.white54,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Contraseña Inicial',
                    labelStyle: TextStyle(color: Colors.white60),
                    prefixIcon: Icon(
                      Icons.lock_outline_rounded,
                      color: Colors.white54,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nombre o Alias',
                    labelStyle: TextStyle(color: Colors.white60),
                    prefixIcon: Icon(
                      Icons.badge_outlined,
                      color: Colors.white54,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Vigencia Inicial:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('30 Días'),
                      selected: initialDays == 30 && !isPermanent,
                      onSelected: (val) => setDialogState(() {
                        initialDays = 30;
                        isPermanent = false;
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('90 Días'),
                      selected: initialDays == 90 && !isPermanent,
                      onSelected: (val) => setDialogState(() {
                        initialDays = 90;
                        isPermanent = false;
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('1 Año'),
                      selected: initialDays == 365 && !isPermanent,
                      onSelected: (val) => setDialogState(() {
                        initialDays = 365;
                        isPermanent = false;
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('💎 Permanente'),
                      selected: isPermanent,
                      selectedColor: Colors.amber.withValues(alpha: 0.3),
                      onSelected: (val) => setDialogState(() {
                        isPermanent = true;
                      }),
                    ),
                  ],
                ),
              ],
            ),
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
                final password = passwordController.text;
                final name = nameController.text.trim();
                if (email.isNotEmpty && password.isNotEmpty) {
                  try {
                    final auth = ref.read(inutilAuthProvider);
                    await auth.adminCreateUser(
                      email: email,
                      password: password,
                      displayName: name,
                      initialDays: initialDays,
                      isPermanent: isPermanent,
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    await _loadUsers();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Usuario $email creado con éxito.'),
                          backgroundColor: InutilDesignSystem.primaryNeon,
                        ),
                      );
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(e.toString()),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: InutilDesignSystem.primaryNeon,
                foregroundColor: Colors.white,
              ),
              child: const Text('Crear Usuario'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredUsers;
    final totalUsers = _users.length;
    final activeUsers = _users.where((u) => u.isActive && !u.isExpired).length;
    final expiredUsers = _users.where((u) => u.isExpired || !u.isActive).length;
    final adminUsers = _users.where((u) => u.isAdmin).length;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 880, maxHeight: 850),
      decoration: BoxDecoration(
        color: InutilDesignSystem.surfaceDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: InutilDesignSystem.borderSubtle, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          // 1. Barra Superior del Panel de Administración
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: InutilDesignSystem.surfaceElevated,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              border: Border(
                bottom: BorderSide(color: InutilDesignSystem.borderSubtle),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_rounded,
                        color: Colors.amberAccent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Panel de Control César',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          color: InutilDesignSystem.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Actualizar Lista',
                      onPressed: _loadUsers,
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar Panel',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white60,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'SuperAdmin: César • Licencias y OTA',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          showInutilAdminPublishUpdateDialog(context),
                      icon: const Icon(
                        Icons.cloud_upload_rounded,
                        size: 14,
                        color: InutilDesignSystem.accentCyan,
                      ),
                      label: const Text(
                        'Publicar OTA',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: InutilDesignSystem.accentCyan,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: InutilDesignSystem.accentCyan.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _showCreateUserDialog,
                      icon: const Icon(Icons.person_add_rounded, size: 14),
                      label: const Text(
                        'Nuevo Usuario',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: InutilDesignSystem.primaryNeon,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Tarjetas de Métricas Resumidas
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            color: InutilDesignSystem.surfaceDark,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStatBadge(
                    'Total',
                    totalUsers.toString(),
                    Colors.blueAccent,
                  ),
                  const SizedBox(width: 12),
                  _buildStatBadge(
                    'Activos',
                    activeUsers.toString(),
                    Colors.greenAccent,
                  ),
                  const SizedBox(width: 12),
                  _buildStatBadge(
                    'Vencidos / Inactivos',
                    expiredUsers.toString(),
                    Colors.redAccent,
                  ),
                  const SizedBox(width: 12),
                  _buildStatBadge(
                    'Admins',
                    adminUsers.toString(),
                    Colors.amberAccent,
                  ),
                ],
              ),
            ),
          ),

          // 3. Barra de Búsqueda y Filtros
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Buscar por correo, nombre o UID...',
                      hintStyle: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Colors.white54,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: InutilDesignSystem.surfaceElevated,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const SizedBox(width: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterButton('Todos', 'todos'),
                      const SizedBox(width: 6),
                      _buildFilterButton('Activos', 'activos'),
                      const SizedBox(width: 6),
                      _buildFilterButton('Vencidos', 'vencidos'),
                      const SizedBox(width: 6),
                      _buildFilterButton('Admins', 'admins'),
                      const SizedBox(width: 6),
                      // Los nuevos registros esperan vigencia: sin aprobarla no
                      // pueden reproducir nada.
                      _buildFilterButton(
                        _pendingCount > 0
                            ? 'Pendientes ($_pendingCount)'
                            : 'Pendientes',
                        'pendientes',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: InutilDesignSystem.borderSubtle, height: 16),

          // 4. Lista de Usuarios
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: InutilDesignSystem.primaryNeon,
                    ),
                  )
                : filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No se encontraron usuarios con este criterio.',
                          style: TextStyle(
                            color: InutilDesignSystem.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final user = filtered[index];
                      return _buildUserCard(user);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton(String label, String filterKey) {
    final isSelected = _selectedFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = filterKey),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? InutilDesignSystem.primaryNeon
              : InutilDesignSystem.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : InutilDesignSystem.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(InutilUser user) {
    final isExpired = user.isExpired;
    final isPending = user.status == 'pending';
    final isSuspended = !user.isActive && !isPending;
    final days = user.daysRemaining;

    Color statusColor;
    String statusText;
    if (user.isAdmin) {
      statusColor = Colors.amberAccent;
      statusText = '👑 ADMIN';
    } else if (isPending) {
      statusColor = Colors.lightBlueAccent;
      statusText = '⏳ PENDIENTE';
    } else if (isSuspended) {
      statusColor = Colors.orangeAccent;
      statusText = '⛔ SUSPENDIDO';
    } else if (isExpired) {
      statusColor = Colors.redAccent;
      statusText = '🔴 VENCIDO';
    } else if (user.isPermanent) {
      statusColor = Colors.cyanAccent;
      statusText = '💎 PERMANENTE';
    } else {
      statusColor = Colors.greenAccent;
      statusText = '🟢 ACTIVO ($days d)';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: InutilDesignSystem.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: user.isAdmin
              ? Colors.amberAccent.withValues(alpha: 0.3)
              : (isExpired || isSuspended)
              ? Colors.redAccent.withValues(alpha: 0.25)
              : InutilDesignSystem.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila Principal: Avatar, Datos e Insignia de Estado
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: statusColor.withValues(alpha: 0.18),
                child: Text(
                  user.displayName.isNotEmpty
                      ? user.displayName[0].toUpperCase()
                      : user.email[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          user.displayName.isNotEmpty
                              ? user.displayName
                              : user.email.split('@').first,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: InutilDesignSystem.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.email,
                      style: const TextStyle(
                        fontSize: 13,
                        color: InutilDesignSystem.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'UID: ${user.uid}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white38,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: user.uid),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'UID copiado al portapapeles',
                                    ),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: const Icon(
                                Icons.copy_rounded,
                                size: 12,
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Vencimiento: ${_formatDate(user.accountExpiresAt)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isExpired
                                ? Colors.redAccent
                                : Colors.white70,
                          ),
                        ),
                        if (!user.isAdmin) ...[
                          // Un solo teléfono por cuenta: el admin puede liberar
                          // el dispositivo desde aquí si el usuario cambió de
                          // equipo o perdió el teléfono.
                          Text(
                            user.currentPhoneDeviceId.isEmpty
                                ? '📱 sin teléfono registrado'
                                : '📱 ${user.currentPhoneDeviceId} · '
                                      'cambios ${user.phoneSwitchCount}/'
                                      '${InutilAuthService.maxMonthlyPhoneSwitches} '
                                      '(${user.phoneSwitchMonth})',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white38,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Botones de acción rápida en cuenta
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: user.isActive
                        ? 'Suspender Cuenta'
                        : 'Activar Cuenta',
                    icon: Icon(
                      user.isActive
                          ? Icons.toggle_on_rounded
                          : Icons.toggle_off_rounded,
                      color: user.isActive ? Colors.greenAccent : Colors.grey,
                      size: 28,
                    ),
                    onPressed: () =>
                        _toggleActive(user.uid, user.isActive, user.email),
                  ),
                  IconButton(
                    tooltip: user.isAdmin
                        ? 'Degradar a Usuario'
                        : 'Ascender a Administrador',
                    icon: Icon(
                      Icons.shield_rounded,
                      color: user.isAdmin ? Colors.amberAccent : Colors.white24,
                      size: 20,
                    ),
                    onPressed: () =>
                        _toggleRole(user.uid, user.role, user.email),
                  ),
                  if (isPending)
                    IconButton(
                      tooltip: 'Aprobar cuenta y dar 30 días de vigencia',
                      icon: const Icon(
                        Icons.fact_check_outlined,
                        color: Colors.lightBlueAccent,
                        size: 22,
                      ),
                      onPressed: () => _approvePending(user),
                    ),
                  if (!user.isAdmin && user.currentPhoneDeviceId.isNotEmpty)
                    IconButton(
                      tooltip:
                          'Liberar teléfono (otro dispositivo podrá tomar la cuenta)',
                      icon: const Icon(
                        Icons.smartphone_rounded,
                        color: InutilDesignSystem.accentCyan,
                        size: 20,
                      ),
                      onPressed: () => _releaseDevice(user.uid, user.email),
                    ),
                  IconButton(
                    tooltip: 'Eliminar Cuenta',
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    onPressed: () => _deleteUserConfirm(user.uid, user.email),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 10),

          // Fila de Gestión de Vigencia (+7d, +30d, +90d, +1a, Permanente, Fecha)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text(
                  'Conceder Vigencia:',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: InutilDesignSystem.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                _buildVigenciaChip(
                  '+7 Días',
                  () => _grantVigencia(user.uid, 7, email: user.email),
                ),
                const SizedBox(width: 6),
                _buildVigenciaChip(
                  '+30 Días (1 Mes)',
                  () => _grantVigencia(user.uid, 30, email: user.email),
                  highlight: true,
                ),
                const SizedBox(width: 6),
                _buildVigenciaChip(
                  '+90 Días (3 Meses)',
                  () => _grantVigencia(user.uid, 90, email: user.email),
                ),
                const SizedBox(width: 6),
                _buildVigenciaChip(
                  '+1 Año',
                  () => _grantVigencia(user.uid, 365, email: user.email),
                ),
                const SizedBox(width: 6),
                _buildVigenciaChip(
                  '💎 Permanente',
                  () => _grantVigencia(
                    user.uid,
                    9999,
                    isPermanent: true,
                    email: user.email,
                  ),
                  color: Colors.amberAccent,
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Elegir fecha de vencimiento en calendario',
                  icon: const Icon(
                    Icons.calendar_month_rounded,
                    size: 18,
                    color: InutilDesignSystem.accentCyan,
                  ),
                  onPressed: () => _pickCustomDate(
                    user.uid,
                    user.email,
                    user.accountExpiresAt,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVigenciaChip(
    String label,
    VoidCallback onTap, {
    bool highlight = false,
    Color? color,
  }) {
    final chipColor =
        color ?? (highlight ? InutilDesignSystem.primaryNeon : Colors.white70);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: highlight
              ? InutilDesignSystem.primaryNeon.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: chipColor.withValues(alpha: highlight ? 0.6 : 0.25),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
            color: chipColor,
          ),
        ),
      ),
    );
  }
}
