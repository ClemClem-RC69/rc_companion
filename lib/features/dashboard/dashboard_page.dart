import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pages/radios_page.dart';
import '../batteries/batteries_page.dart';
import '../maintenance/maintenance_page.dart';
import '../models/models_page.dart';
import '../sessions/sessions_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  void open(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Future<void> logout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Déconnexion'),
          content: const Text(
            'Veux-tu vraiment te déconnecter de RC Companion ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Se déconnecter'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) {
      return;
    }

    try {
      await Supabase.instance.client.auth.signOut();

      if (!context.mounted) {
        return;
      }

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la déconnexion : $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = Supabase.instance.client.auth.currentUser?.email;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RC Companion'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => logout(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Mon garage RC',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (userEmail != null) ...[
            const SizedBox(height: 6),
            Text(
              'Connecté avec $userEmail',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),
          HomeCard(
            icon: Icons.directions_car,
            title: 'Mes modèles',
            subtitle: 'Voitures et bateaux',
            onTap: () => open(context, const ModelsPage()),
          ),
          HomeCard(
            icon: Icons.settings_remote,
            title: 'Mes radios',
            subtitle: 'Catalogue, profils et réglages radio',
            onTap: () => open(context, const RadiosPage()),
          ),
          HomeCard(
            icon: Icons.battery_charging_full,
            title: 'Mes batteries',
            subtitle: 'Technologie, capacité, C, QR Code et paires',
            onTap: () => open(context, const BatteriesPage()),
          ),
          HomeCard(
            icon: Icons.route,
            title: 'Nouvelle session',
            subtitle: 'Enregistrer une sortie',
            onTap: () => open(context, const SessionsPage()),
          ),
          HomeCard(
            icon: Icons.build,
            title: 'Entretiens',
            subtitle: 'Réparations, réglages et modifications',
            onTap: () => open(context, const MaintenancePage()),
          ),
        ],
      ),
    );
  }
}

class HomeCard extends StatelessWidget {
  const HomeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
        leading: Icon(icon, size: 34),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
