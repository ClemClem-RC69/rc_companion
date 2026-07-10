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
          _ModelPhotoHeader(model: model),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(
                _iconForCategory(model.category),
                size: 36,
              ),
              title: Text(
                model.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
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

class _ModelPhotoHeader extends StatelessWidget {
  const _ModelPhotoHeader({
    required this.model,
  });

  final RcModel model;

  @override
  Widget build(BuildContext context) {
    final photoUrl = model.photoUrl;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.infinity,
        height: 280,
        child: photoUrl != null && photoUrl.trim().isNotEmpty
            ? Container(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                alignment: Alignment.center,
                child: Image.network(
                  photoUrl,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                  loadingBuilder: (
                    context,
                    child,
                    loadingProgress,
                  ) {
                    if (loadingProgress == null) {
                      return child;
                    }

                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  },
                  errorBuilder: (_, __, ___) {
                    return _EmptyModelPhoto(
                      category: model.category,
                    );
                  },
                ),
              )
            : _EmptyModelPhoto(
                category: model.category,
              ),
      ),
    );
  }
}

class _EmptyModelPhoto extends StatelessWidget {
  const _EmptyModelPhoto({
    required this.category,
  });

  final String category;

  IconData get icon {
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 72,
          ),
          const SizedBox(height: 12),
          const Text('Aucune photo'),
        ],
      ),
    );
  }
}