import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../models/rc_model.dart';

class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key});

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  void addModel() async {
    final model = await Navigator.push<RcModel>(
      context,
      MaterialPageRoute(builder: (_) => const AddModelPage()),
    );

    if (model != null) {
      setState(() => models.add(model));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes modèles')),
      body: models.isEmpty
          ? const Center(child: Text('Aucun modèle pour le moment', style: TextStyle(fontSize: 22)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: models.length,
              itemBuilder: (context, index) {
                final model = models[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.directions_car, size: 36),
                    title: Text(model.name),
                    subtitle: Text(
                      '${model.brand} • ${model.category} • ${model.scale} • ${model.batteryCount} × ${model.maxCells} max',
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addModel,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
    );
  }
}

class AddModelPage extends StatefulWidget {
  const AddModelPage({super.key});

  @override
  State<AddModelPage> createState() => _AddModelPageState();
}

class _AddModelPageState extends State<AddModelPage> {
  final nameController = TextEditingController();
  final brandController = TextEditingController();

  String category = 'Voiture';
  String motorization = 'Électrique';
  String scale = '1/10';
  int batteryCount = 1;
  String maxCells = '4S';

  final categories = ['Voiture', 'Bateau', 'Avion', 'Hélicoptère', 'Drone'];
  final motorisations = ['Électrique', 'Thermique'];
  final scales = ['1/24', '1/18', '1/16', '1/14', '1/12', '1/10', '1/8', '1/7', '1/6', '1/5', 'Autre'];
  final cellOptions = ['1S', '2S', '3S', '4S', '5S', '6S'];

  void save() {
    final name = nameController.text.trim();
    final brand = brandController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indique un nom de modèle')),
      );
      return;
    }

    Navigator.pop(
      context,
      RcModel(
        name: name,
        brand: brand.isEmpty ? 'Marque non renseignée' : brand,
        category: category,
        motorization: motorization,
        scale: scale,
        batteryCount: motorization == 'Électrique' ? batteryCount : 0,
        maxCells: motorization == 'Électrique' ? maxCells : 'Aucune',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau modèle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nom du modèle', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          TextField(controller: brandController, decoration: const InputDecoration(labelText: 'Marque', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: category,
            decoration: const InputDecoration(labelText: 'Catégorie', border: OutlineInputBorder()),
            items: categories.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => setState(() => category = value!),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: motorization,
            decoration: const InputDecoration(labelText: 'Motorisation', border: OutlineInputBorder()),
            items: motorisations.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => setState(() => motorization = value!),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: scale,
            decoration: const InputDecoration(labelText: 'Échelle', border: OutlineInputBorder()),
            items: scales.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => setState(() => scale = value!),
          ),
          const SizedBox(height: 14),
          if (motorization == 'Électrique') ...[
            DropdownButtonFormField<int>(
              value: batteryCount,
              decoration: const InputDecoration(labelText: 'Nombre de batteries', border: OutlineInputBorder()),
              items: [1, 2].map((item) => DropdownMenuItem(value: item, child: Text('$item batterie(s)'))).toList(),
              onChanged: (value) => setState(() => batteryCount = value!),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: maxCells,
              decoration: const InputDecoration(labelText: 'Type max par batterie', border: OutlineInputBorder()),
              items: cellOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
              onChanged: (value) => setState(() => maxCells = value!),
            ),
            const SizedBox(height: 14),
          ],
          FilledButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('Enregistrer')),
        ],
      ),
    );
  }
}
