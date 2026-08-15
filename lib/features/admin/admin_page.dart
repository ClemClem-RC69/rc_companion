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
    if (_users.isEmpty)
      return const Center(child: Text('Aucun compte à afficher.'));

    return ListView.separated(
      itemCount: _users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = _users[index];
        final admin = row['is_admin'] == true;
        return Card(
          child: ListTile(
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
