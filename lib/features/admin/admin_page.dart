import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
            const Text(
              'Gestion des comptes',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Consultation uniquement pour cette première étape.',
              style: TextStyle(color: RCColors.textSecondary),
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
        return Card(
          child: ListTile(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _AdminUserDetailPage(user: row),
                ),
              );
            },
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 10,
            ),
            leading: Icon(
              admin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
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
              admin
                  ? 'ADMIN'
                  : (row['enabled'] == false ? 'DÉSACTIVÉ' : 'ACTIF'),
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

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  String _value(String key) {
    final value = widget.user[key];
    return value == null || value.toString().trim().isEmpty
        ? '—'
        : value.toString();
  }

  Future<void> _loadDevices() async {
    final authUserId = widget.user['auth_user_id']?.toString().trim();

    if (authUserId == null || authUserId.isEmpty) {
      setState(() {
        _loading = false;
        _error =
            'Ce compte autorisé n’a pas encore de compte Authentication associé.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

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

  @override
  Widget build(BuildContext context) {
    final pseudo = _value('pseudo');
    final email = _value('email');
    final admin = widget.user['is_admin'] == true;
    final enabled = widget.user['enabled'] != false;

    return Scaffold(
      appBar: AppBar(
        title: Text(pseudo == '—' ? email : pseudo),
        actions: [
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
                      admin
                          ? Icons.admin_panel_settings_rounded
                          : Icons.person_rounded,
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
                        admin ? 'ADMIN' : (enabled ? 'ACTIF' : 'DÉSACTIVÉ'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Autorisations par plateforme',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
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
              trailing: Chip(label: Text(active ? 'ACTIF' : 'INACTIF')),
            ),
          ),
        );
      }).toList(),
    );
  }
}
