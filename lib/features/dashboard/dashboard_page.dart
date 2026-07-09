import 'package:flutter/material.dart';

import '../batteries/batteries_page.dart';
import '../maintenance/maintenance_page.dart';
import '../models/models_page.dart';
import '../sessions/sessions_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  void open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RC Companion'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Mon garage RC', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          HomeCard(icon: Icons.directions_car, title: 'Mes modèles', subtitle: 'Voitures, bateaux, avions, drones et hélicos', onTap: () => open(context, const ModelsPage())),
          HomeCard(icon: Icons.battery_charging_full, title: 'Mes batteries', subtitle: 'Technologie, capacité, C, QR Code et paires', onTap: () => open(context, const BatteriesPage())),
          HomeCard(icon: Icons.route, title: 'Nouvelle session', subtitle: 'Enregistrer une sortie', onTap: () => open(context, const SessionsPage())),
          HomeCard(icon: Icons.build, title: 'Entretiens', subtitle: 'Réparations, réglages et modifications', onTap: () => open(context, const MaintenancePage())),
        ],
      ),
    );
  }
}

class HomeCard extends StatelessWidget {
  const HomeCard({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

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
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
