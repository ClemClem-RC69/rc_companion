import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app.dart';
import '../../services/supabase_service.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = const [];
  Timer? _usersWatchdog;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _usersWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _loadUsers(showLoading: false);
    });
  }

  @override
  void dispose() {
    _usersWatchdog?.cancel();
    super.dispose();
  }

  Future<void> _loadUsers({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await SupabaseService.client.rpc('rc_admin_list_users');
      final rows = <Map<String, dynamic>>[];
      if (response is List) {
        for (final item in response) {
          if (item is Map) {
            rows.add(item.map((key, value) => MapEntry(key.toString(), value)));
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _users = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addUser() async {
    final emailController = TextEditingController();
    final androidController = TextEditingController(text: '1');
    final windowsController = TextEditingController(text: '1');
    final macosController = TextEditingController(text: '1');
    final iosController = TextEditingController(text: '1');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ajouter un utilisateur'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Préautorise l’adresse e-mail avant la création du compte RC Companion.',
                      style: TextStyle(color: RCColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Adresse e-mail',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Nombre d’appareils simultanés autorisés',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: androidController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Android',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: windowsController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Windows',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: macosController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'macOS'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: iosController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'iOS'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              onPressed: () {
                final email = emailController.text.trim().toLowerCase();
                final android = int.tryParse(androidController.text.trim());
                final windows = int.tryParse(windowsController.text.trim());
                final macos = int.tryParse(macosController.text.trim());
                final ios = int.tryParse(iosController.text.trim());

                if (!email.contains('@') ||
                    android == null ||
                    windows == null ||
                    macos == null ||
                    ios == null ||
                    android < 0 ||
                    windows < 0 ||
                    macos < 0 ||
                    ios < 0) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Vérifie l’adresse e-mail et les quatre quotas.',
                      ),
                    ),
                  );
                  return;
                }

                Navigator.of(dialogContext).pop(<String, dynamic>{
                  'email': email,
                  'max_android': android,
                  'max_windows': windows,
                  'max_macos': macos,
                  'max_ios': ios,
                });
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Ajouter'),
            ),
          ],
        );
      },
    );

    emailController.dispose();
    androidController.dispose();
    windowsController.dispose();
    macosController.dispose();
    iosController.dispose();

    if (result == null || !mounted) return;

    try {
      await SupabaseService.client.rpc(
        'rc_admin_add_user',
        params: <String, dynamic>{
          'p_email': result['email'],
          'p_max_android': result['max_android'],
          'p_max_windows': result['max_windows'],
          'p_max_macos': result['max_macos'],
          'p_max_ios': result['max_ios'],
        },
      );

      if (!mounted) return;
      await _loadUsers(showLoading: false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Utilisateur ${result['email']} préautorisé. Il peut maintenant créer son compte.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ajout impossible : $error')));
    }
  }

  Future<void> _signOut() => SupabaseService.client.auth.signOut();

  String _value(Map<String, dynamic> row, String key) {
    final value = row[key];
    return value == null || value.toString().trim().isEmpty
        ? '—'
        : value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration RC Companion'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _loadUsers,
            icon: const Icon(Icons.refresh_rounded),
          ),
          TextButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Se déconnecter'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Gestion des comptes',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _addUser,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Ajouter un utilisateur'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Impossible de charger les comptes',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                SelectableText(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loadUsers,
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_users.isEmpty) {
      return const Center(child: Text('Aucun compte à afficher.'));
    }

    return ListView.separated(
      itemCount: _users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = _users[index];
        final admin = row['is_admin'] == true;
        final email = _value(row, 'email').toLowerCase();
        final owner = email == 'clementgabriac@gmail.com';
        return Card(
          child: ListTile(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _AdminUserDetailPage(user: row),
                ),
              );
              if (!context.mounted) return;
              await _loadUsers();
            },
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 10,
            ),
            leading: Icon(
              owner
                  ? Icons.workspace_premium_rounded
                  : (admin
                        ? Icons.admin_panel_settings_rounded
                        : Icons.person_rounded),
            ),
            title: Text(
              _value(row, 'pseudo') == '—'
                  ? _value(row, 'email')
                  : _value(row, 'pseudo'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _value(row, 'pseudo') == '—'
                    ? 'Android : ${_value(row, 'max_android')}  •  '
                          'Windows : ${_value(row, 'max_windows')}  •  '
                          'macOS : ${_value(row, 'max_macos')}  •  '
                          'iOS : ${_value(row, 'max_ios')}'
                    : '${_value(row, 'email')}\n'
                          'Android : ${_value(row, 'max_android')}  •  '
                          'Windows : ${_value(row, 'max_windows')}  •  '
                          'macOS : ${_value(row, 'max_macos')}  •  '
                          'iOS : ${_value(row, 'max_ios')}',
              ),
            ),
            trailing: Text(
              owner
                  ? 'PROPRIÉTAIRE • ILLIMITÉ'
                  : (admin
                        ? 'ADMIN'
                        : (row['enabled'] == false ? 'DÉSACTIVÉ' : 'ACTIF')),
            ),
          ),
        );
      },
    );
  }
}

class _AdminUserDetailPage extends StatefulWidget {
  const _AdminUserDetailPage({required this.user});

  final Map<String, dynamic> user;

  @override
  State<_AdminUserDetailPage> createState() => _AdminUserDetailPageState();
}

class _AdminUserDetailPageState extends State<_AdminUserDetailPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _devices = const [];
  RealtimeChannel? _devicesChannel;
  Timer? _devicesWatchdog;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _subscribeToDeviceChanges();
    _devicesWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _loadDevices(showLoading: false);
    });
  }

  void _subscribeToDeviceChanges() {
    final authUserId = widget.user['auth_user_id']?.toString().trim();
    if (authUserId == null || authUserId.isEmpty) return;

    _devicesChannel = SupabaseService.client
        .channel('admin-user-devices-$authUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_devices',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: authUserId,
          ),
          callback: (_) {
            if (!mounted) return;
            _loadDevices(showLoading: false);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _devicesWatchdog?.cancel();
    final channel = _devicesChannel;
    if (channel != null) {
      SupabaseService.client.removeChannel(channel);
    }
    super.dispose();
  }

  String _value(String key) {
    final value = widget.user[key];
    return value == null || value.toString().trim().isEmpty
        ? '—'
        : value.toString();
  }

  Future<void> _loadDevices({bool showLoading = true}) async {
    final authUserId = widget.user['auth_user_id']?.toString().trim();

    if (authUserId == null || authUserId.isEmpty) {
      setState(() {
        _loading = false;
        _error =
            'Ce compte autorisé n’a pas encore de compte Authentication associé.';
      });
      return;
    }

    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final response = await SupabaseService.client.rpc(
        'rc_admin_list_user_devices',
        params: <String, dynamic>{'p_auth_user_id': authUserId},
      );

      final rows = <Map<String, dynamic>>[];
      if (response is List) {
        for (final item in response) {
          if (item is Map) {
            rows.add(item.map((key, value) => MapEntry(key.toString(), value)));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _devices = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _platformLabel(String? platform) {
    switch (platform) {
      case 'android':
        return 'Android';
      case 'windows':
        return 'Windows';
      case 'macos':
        return 'macOS';
      case 'ios':
        return 'iPhone / iPad';
      default:
        return platform == null || platform.isEmpty ? 'Inconnue' : platform;
    }
  }

  IconData _platformIcon(String? platform) {
    switch (platform) {
      case 'android':
        return Icons.android_rounded;
      case 'windows':
        return Icons.desktop_windows_rounded;
      case 'macos':
        return Icons.laptop_mac_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return 'Jamais';
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return raw.toString();

    final local = parsed.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _quota(String label, String key) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(color: RCColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                _value(key),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _quotaValue(String key) {
    final raw = widget.user[key];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  bool get _isProtectedAdminAccount =>
      _value('email').toLowerCase() == 'rccompanion.app@gmail.com';

  bool get _isProtectedOwnerAccount =>
      _value('email').toLowerCase() == 'clementgabriac@gmail.com';

  bool get _isProtectedAccount =>
      _isProtectedAdminAccount || _isProtectedOwnerAccount;

  Future<void> _editUser() async {
    if (_isProtectedAccount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ce compte RC Companion est protégé et ne peut pas être modifié ici.',
          ),
        ),
      );
      return;
    }

    var enabled = widget.user['enabled'] != false;
    final androidController = TextEditingController(
      text: _quotaValue('max_android').toString(),
    );
    final windowsController = TextEditingController(
      text: _quotaValue('max_windows').toString(),
    );
    final macosController = TextEditingController(
      text: _quotaValue('max_macos').toString(),
    );
    final iosController = TextEditingController(
      text: _quotaValue('max_ios').toString(),
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget quotaField({
              required String label,
              required TextEditingController controller,
            }) {
              return TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: label),
              );
            }

            return AlertDialog(
              title: const Text('Modifier l’utilisateur'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _value('pseudo') == '—'
                              ? _value('email')
                              : _value('pseudo'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _value('email'),
                          style: const TextStyle(color: RCColors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Compte autorisé',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          enabled
                              ? 'Le compte peut utiliser RC Companion.'
                              : 'Le compte est suspendu.',
                        ),
                        value: enabled,
                        onChanged: (value) {
                          setDialogState(() => enabled = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Nombre d’appareils simultanés autorisés',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: quotaField(
                              label: 'Android',
                              controller: androidController,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: quotaField(
                              label: 'Windows',
                              controller: windowsController,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: quotaField(
                              label: 'macOS',
                              controller: macosController,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: quotaField(
                              label: 'iOS',
                              controller: iosController,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (!_isProtectedAccount)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      Future<void>.delayed(Duration.zero, _deleteUserAccount);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: RCColors.accent,
                    ),
                    icon: const Icon(Icons.delete_forever_rounded),
                    label: const Text('Supprimer le compte'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () {
                    final android = int.tryParse(androidController.text.trim());
                    final windows = int.tryParse(windowsController.text.trim());
                    final macos = int.tryParse(macosController.text.trim());
                    final ios = int.tryParse(iosController.text.trim());

                    if (android == null ||
                        windows == null ||
                        macos == null ||
                        ios == null ||
                        android < 0 ||
                        windows < 0 ||
                        macos < 0 ||
                        ios < 0) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Chaque quota doit être un nombre entier positif ou nul.',
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.of(dialogContext).pop(<String, dynamic>{
                      'enabled': enabled,
                      'max_android': android,
                      'max_windows': windows,
                      'max_macos': macos,
                      'max_ios': ios,
                    });
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    androidController.dispose();
    windowsController.dispose();
    macosController.dispose();
    iosController.dispose();

    if (result == null || !mounted) return;

    try {
      await SupabaseService.client.rpc(
        'rc_admin_update_user',
        params: <String, dynamic>{
          'p_email': _value('email'),
          'p_enabled': result['enabled'],
          'p_max_android': result['max_android'],
          'p_max_windows': result['max_windows'],
          'p_max_macos': result['max_macos'],
          'p_max_ios': result['max_ios'],
        },
      );

      if (!mounted) return;

      setState(() {
        widget.user['enabled'] = result['enabled'];
        widget.user['max_android'] = result['max_android'];
        widget.user['max_windows'] = result['max_windows'];
        widget.user['max_macos'] = result['max_macos'];
        widget.user['max_ios'] = result['max_ios'];
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Utilisateur mis à jour.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Modification impossible : $error')),
      );
    }
  }

  Future<void> _removeDeletedEmailFromLocalMemory(String email) async {
    const rememberedKey = 'rc_remembered_login_emails_v1';
    const lastKey = 'rc_last_remembered_login_email_v1';

    final normalized = email.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();

    final remembered =
        (prefs.getStringList(rememberedKey) ?? const <String>[])
            .where((item) => item.trim().toLowerCase() != normalized)
            .toList()
          ..sort();

    await prefs.setStringList(rememberedKey, remembered);

    if (prefs.getString(lastKey)?.trim().toLowerCase() == normalized) {
      await prefs.remove(lastKey);
    }
  }

  Future<void> _deleteUserAccount() async {
    if (_isProtectedAccount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ce compte RC Companion est protégé et ne peut pas être supprimé.',
          ),
        ),
      );
      return;
    }

    final authUserId = widget.user['auth_user_id']?.toString().trim();
    final email = _value('email').trim();

    if (authUserId == null || authUserId.isEmpty || email == '—') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Suppression impossible : compte Authentication introuvable.',
          ),
        ),
      );
      return;
    }

    final confirmController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var canDelete = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final mediaQuery = MediaQuery.of(dialogContext);
            final isPhone = mediaQuery.size.width < 600;
            final keyboardHeight = mediaQuery.viewInsets.bottom;
            final maxDialogHeight =
                mediaQuery.size.height - keyboardHeight - (isPhone ? 32 : 64);

            return AlertDialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: isPhone ? 16 : 40,
                vertical: isPhone ? 16 : 24,
              ),
              title: const Text('Supprimer définitivement ce compte ?'),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 560,
                  maxHeight: maxDialogHeight.clamp(220.0, 700.0),
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Cette action est définitive. Le compte utilisateur, ses '
                        'appareils et toutes ses données serveur RC Companion '
                        'seront supprimés. Cette opération est irréversible.',
                        style: TextStyle(
                          color: RCColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Pour confirmer, saisissez SUPPRIMER :',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: confirmController,
                        autofocus: true,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          hintText: 'SUPPRIMER',
                        ),
                        onChanged: (value) {
                          final next =
                              value.trim().toUpperCase() == 'SUPPRIMER';
                          if (next != canDelete) {
                            setDialogState(() => canDelete = next);
                          }
                        },
                        onSubmitted: (_) {
                          if (canDelete) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actionsOverflowAlignment: OverflowBarAlignment.end,
              actionsOverflowDirection: VerticalDirection.down,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton.icon(
                  onPressed: canDelete
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: RCColors.accent,
                  ),
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Supprimer définitivement'),
                ),
              ],
            );
          },
        );
      },
    );

    confirmController.dispose();

    if (confirmed != true || !mounted) return;

    try {
      final response = await SupabaseService.client.rpc(
        'rc_admin_delete_user',
        params: <String, dynamic>{
          'p_auth_user_id': authUserId,
          'p_email': email,
        },
      );

      if (!mounted) return;

      final deleted = response is Map && response['deleted'] == true;
      if (!deleted) {
        throw StateError(
          'La suppression n’a pas été confirmée par le serveur.',
        );
      }

      await _removeDeletedEmailFromLocalMemory(email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Compte utilisateur et données supprimés définitivement.',
          ),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Suppression impossible : $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pseudo = _value('pseudo');
    final email = _value('email');
    final admin = widget.user['is_admin'] == true;
    final enabled = widget.user['enabled'] != false;
    final owner = _isProtectedOwnerAccount;

    return Scaffold(
      appBar: AppBar(
        title: Text(pseudo == '—' ? email : pseudo),
        actions: [
          if (!_isProtectedAccount)
            TextButton.icon(
              onPressed: _editUser,
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Modifier'),
            ),
          IconButton(
            tooltip: 'Actualiser les appareils',
            onPressed: _loading ? null : _loadDevices,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      owner
                          ? Icons.workspace_premium_rounded
                          : (admin
                                ? Icons.admin_panel_settings_rounded
                                : Icons.person_rounded),
                      size: 42,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pseudo == '—' ? email : pseudo,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (pseudo != '—') ...[
                            const SizedBox(height: 3),
                            Text(
                              email,
                              style: const TextStyle(
                                color: RCColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Chip(
                      label: Text(
                        owner
                            ? 'PROPRIÉTAIRE • ILLIMITÉ'
                            : (admin
                                  ? 'ADMIN'
                                  : (enabled ? 'ACTIF' : 'DÉSACTIVÉ')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isProtectedAdminAccount) ...[
              const SizedBox(height: 10),
              const Text(
                'Compte administrateur protégé : ses autorisations ne sont pas modifiables depuis cette fiche.',
                style: TextStyle(
                  color: RCColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (_isProtectedOwnerAccount) ...[
              const SizedBox(height: 10),
              const Text(
                'Compte propriétaire protégé : accès illimité sur Android, Windows, macOS et iPhone / iPad. Ce compte n’est pas administrateur et ses autorisations ne sont pas modifiables depuis cette fiche.',
                style: TextStyle(
                  color: RCColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Autorisations par plateforme',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (_isProtectedOwnerAccount)
              const Card(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.all_inclusive_rounded),
                      SizedBox(width: 10),
                      Text(
                        'ILLIMITÉ • Android • Windows • macOS • iPhone / iPad',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              )
            else
              Row(
                children: [
                  _quota('Android', 'max_android'),
                  const SizedBox(width: 10),
                  _quota('Windows', 'max_windows'),
                  const SizedBox(width: 10),
                  _quota('macOS', 'max_macos'),
                  const SizedBox(width: 10),
                  _quota('iOS', 'max_ios'),
                ],
              ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Appareils enregistrés',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${_devices.length} appareil(s)',
                  style: const TextStyle(color: RCColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildDevices(),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDeviceAction({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: destructive
                  ? FilledButton.styleFrom(backgroundColor: RCColors.accent)
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> _manageDevice(Map<String, dynamic> device, String action) async {
    final rowId = device['id']?.toString().trim();
    if (rowId == null || rowId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identifiant appareil introuvable.')),
      );
      return;
    }

    final name = device['device_name']?.toString().trim();
    final platform = _platformLabel(device['platform']?.toString());
    final displayName = name == null || name.isEmpty ? platform : name;

    var confirmed = false;

    if (action == 'activate') {
      confirmed = await _confirmDeviceAction(
        title: 'Activer cet appareil ?',
        message:
            '$displayName sera autorisé à utiliser RC Companion et occupera '
            'une place dans le quota $platform du compte.',
        confirmLabel: 'Activer',
      );
    } else if (action == 'deactivate') {
      confirmed = await _confirmDeviceAction(
        title: 'Désactiver cet appareil ?',
        message:
            '$displayName restera enregistré dans l’administration, mais il '
            'ne pourra plus utiliser RC Companion et libérera sa place dans '
            'le quota $platform.',
        confirmLabel: 'Désactiver',
      );
    } else if (action == 'delete') {
      confirmed = await _confirmDeviceAction(
        title: 'Supprimer définitivement cet appareil ?',
        message:
            '$displayName sera retiré définitivement de la liste des appareils '
            'enregistrés. S’il se reconnecte plus tard, il sera considéré '
            'comme un nouvel appareil.',
        confirmLabel: 'Supprimer',
        destructive: true,
      );
    }

    if (!confirmed || !mounted) return;

    try {
      await SupabaseService.client.rpc(
        'rc_admin_manage_device',
        params: <String, dynamic>{'p_device_row_id': rowId, 'p_action': action},
      );

      if (!mounted) return;

      await _loadDevices();

      if (!mounted) return;

      final message = switch (action) {
        'activate' => 'Appareil activé.',
        'deactivate' => 'Appareil désactivé.',
        'delete' => 'Appareil supprimé.',
        _ => 'Appareil mis à jour.',
      };

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action impossible : ${error.toString()}')),
      );
    }
  }

  Widget _buildDevices() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: RCColors.warning,
                size: 38,
              ),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: RCColors.textSecondary),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _loadDevices,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (_devices.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(22),
          child: Text(
            'Aucun appareil enregistré pour ce compte.',
            textAlign: TextAlign.center,
            style: TextStyle(color: RCColors.textSecondary),
          ),
        ),
      );
    }

    return Column(
      children: _devices.map((device) {
        final platform = device['platform']?.toString();
        final active = device['active'] == true;
        final name = device['device_name']?.toString().trim();

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              leading: Icon(_platformIcon(platform), size: 32),
              title: Text(
                name == null || name.isEmpty ? _platformLabel(platform) : name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${_platformLabel(platform)}  •  '
                'Dernière activité : ${_formatDate(device['last_seen_at'])}',
              ),
              trailing: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(label: Text(active ? 'ACTIVÉ' : 'DÉSACTIVÉ')),
                  PopupMenuButton<String>(
                    tooltip: 'Gérer cet appareil',
                    onSelected: (action) => _manageDevice(device, action),
                    itemBuilder: (context) => [
                      if (active)
                        const PopupMenuItem<String>(
                          value: 'deactivate',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.pause_circle_outline_rounded),
                            title: Text('Désactiver'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        )
                      else
                        const PopupMenuItem<String>(
                          value: 'activate',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.play_circle_outline_rounded),
                            title: Text('Activer'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.delete_forever_rounded,
                            color: RCColors.accent,
                          ),
                          title: Text(
                            'Supprimer',
                            style: TextStyle(color: RCColors.accent),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
