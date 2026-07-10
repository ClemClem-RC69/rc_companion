import 'package:flutter/material.dart';

import '../../models/rc_model.dart';

class ModelDetailPage extends StatelessWidget {
  const ModelDetailPage({
    super.key,
    required this.model,
  });

  final RcModel model;

  @override
  Widget build(BuildContext context) {
    final isElectric = model.motorization == 'Électrique';

    return Scaffold(
      appBar: AppBar(
        title: Text(model.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                _iconForCategory(model.category),
                size: 36,
              ),
              title: Text(model.name),
              subtitle: Text(
                '${model.brand} • ${model.category} • ${model.scale}',
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Informations',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          _infoCard(
            icon: Icons.category,
            title: 'Catégorie',
            value: model.category,
          ),
          if (model.discipline.isNotEmpty)
            _infoCard(
              icon: Icons.sports_motorsports,
              title: 'Discipline',
              value: model.discipline,
            ),
          _infoCard(
            icon: Icons.settings,
            title: 'Motorisation',
            value: model.motorization,
          ),
          _infoCard(
            icon: Icons.straighten,
            title: 'Échelle',
            value: model.scale,
          ),
          if (isElectric) ...[
            const SizedBox(height: 20),
            const Text(
              'Configuration électrique',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            _infoCard(
              icon: Icons.battery_charging_full,
              title: 'Nombre de batteries',
              value: '${model.batteryCount}',
            ),
            _infoCard(
              icon: Icons.flash_on,
              title: 'Configuration maximale',
              value: model.maxCells,
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Text(value),
      ),
    );
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'Bateau':
        return Icons.sailing;
      case 'Avion':
        return Icons.flight;
      case 'Hélicoptère':
        return Icons.air;
      case 'Drone':
        return Icons.flight_takeoff;
      case 'Voiture':
      default:
        return Icons.directions_car;
    }
  }
}