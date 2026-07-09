import 'package:flutter/material.dart';
import '../../models/rc_model.dart';

class ModelDetailPage extends StatelessWidget {
  final RcModel model;

  const ModelDetailPage({
    super.key,
    required this.model,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(model.name),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Ajout d'une batterie (à faire ensuite)
        },
        icon: const Icon(Icons.add),
        label: const Text("Ajouter une batterie"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          Card(
            child: ListTile(
              leading: const Icon(Icons.directions_car),
              title: Text(model.name),
              subtitle: Text(
                "${model.brand} • ${model.category} • ${model.scale}",
              ),
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            "Configuration",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          Card(
            child: ListTile(
              leading: const Icon(Icons.battery_charging_full),
              title: const Text("Nombre de batteries"),
              trailing: Text("${model.batteryCount}"),
            ),
          ),

          Card(
            child: ListTile(
              leading: const Icon(Icons.flash_on),
              title: const Text("Configuration maximale"),
              trailing: Text("${model.maxCells}"),
            ),
          ),

          const SizedBox(height: 30),

          const Text(
            "Batteries compatibles",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text("Aucune batterie associée"),
              subtitle: const Text(
                "Vous pourrez associer des batteries à ce modèle.",
              ),
            ),
          ),
        ],
      ),
    );
  }
}