import 'package:flutter/material.dart';

import '../../services/google_drive_service.dart';

class GoogleDriveSettingsSection extends StatefulWidget {
  const GoogleDriveSettingsSection({super.key});

  @override
  State<GoogleDriveSettingsSection> createState() =>
      _GoogleDriveSettingsSectionState();
}

class _GoogleDriveSettingsSectionState
    extends State<GoogleDriveSettingsSection> {
  GoogleDriveConnectionState? _state;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  Future<void> _refreshState() async {
    try {
      final state = await GoogleDriveService.connectionState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Impossible de vérifier Google Drive : $error');
    }
  }

  Future<void> _connect() async {
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await GoogleDriveService.connectDesktop();
      if (!mounted) return;
      await _refreshState();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await GoogleDriveService.disconnect();
      if (!mounted) return;
      await _refreshState();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Déconnexion Google Drive impossible : $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _connectedAccountText(GoogleDriveConnectionState? state) {
    final email = state?.accountEmail?.trim();
    final name = state?.accountName?.trim();

    if (email != null && email.isNotEmpty) {
      if (name != null && name.isNotEmpty) {
        return 'Google Drive connecté : $name — $email';
      }
      return 'Google Drive connecté : $email';
    }

    return 'Google Drive est connecté pour le compte RC Companion '
        'actuellement utilisé.';
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final connected = state?.connected == true;
    final supported = state?.supported ?? true;
    final configured = state?.configured ?? false;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1A2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF23405E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                connected ? Icons.cloud_done_rounded : Icons.cloud_outlined,
                color: connected
                    ? const Color(0xFF45B86B)
                    : const Color(0xFF168CFF),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Stockage & sauvegarde — Google Drive',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            connected
                ? _connectedAccountText(state)
                : state?.message ??
                      'Google Drive personnel est facultatif et servira à '
                          'sauvegarder et synchroniser les fichiers volumineux '
                          'de RC Companion entre tes appareils.',
            style: const TextStyle(color: Color(0xFFB9C5D4), fontSize: 13),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_state == null)
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (!supported)
            const Text(
              'Aucune action nécessaire sur cet appareil pour cette étape.',
              style: TextStyle(
                color: Color(0xFF7F8DA0),
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            )
          else if (!configured)
            const Text(
              'Configuration Desktop requise au lancement de l’application.',
              style: TextStyle(
                color: Color(0xFFFFC857),
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            )
          else if (connected)
            OutlinedButton.icon(
              onPressed: _working ? null : _disconnect,
              icon: _working
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_off_rounded),
              label: const Text('Déconnecter Google Drive'),
            )
          else
            FilledButton.icon(
              onPressed: _working ? null : _connect,
              icon: _working
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_to_drive_rounded),
              label: Text(
                _working ? 'Connexion en cours...' : 'Connecter Google Drive',
              ),
            ),
        ],
      ),
    );
  }
}
