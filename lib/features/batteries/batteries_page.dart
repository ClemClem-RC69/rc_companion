import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../models/battery.dart';
import 'battery_detail_page.dart';

class BatteriesPage extends StatefulWidget {
  const BatteriesPage({super.key});

  @override
  State<BatteriesPage> createState() => _BatteriesPageState();
}

class _BatteriesPageState extends State<BatteriesPage> {
  void addBattery() async {
    final created = await Navigator.push<List<Battery>>(
      context,
      MaterialPageRoute(builder: (_) => const AddBatteryPage()),
    );

    if (created != null) {
      setState(() => batteries.addAll(created));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes batteries')),
      body: batteries.isEmpty
          ? const Center(child: Text('Aucune batterie pour le moment', style: TextStyle(fontSize: 22)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: batteries.length,
              itemBuilder: (context, index) {
                final battery = batteries[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.battery_charging_full, size: 36),
                    title: Text(battery.id),
                    subtitle: Text(
                      '${battery.technology} • ${battery.brand} • ${battery.cells} • ${battery.capacity} mAh • ${battery.cRate}C'
                      '${battery.pairId == null ? '' : ' • Paire ${battery.pairId}'}',
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => BatteryDetailPage(battery: battery)),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addBattery,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
    );
  }
}

class AddBatteryPage extends StatefulWidget {
  const AddBatteryPage({super.key});

  @override
  State<AddBatteryPage> createState() => _AddBatteryPageState();
}

class _AddBatteryPageState extends State<AddBatteryPage> {
  final brandController = TextEditingController();
  final capacityController = TextEditingController(text: '6200');
  final cRateController = TextEditingController(text: '90');

  String technology = 'LiPo';
  String cells = '4S';
  bool createPair = false;

  final technologies = ['LiPo', 'LiHV', 'Li-Ion', 'LiFe', 'NiMH', 'NiCd'];
  final cellOptions = ['1S', '2S', '3S', '4S', '5S', '6S'];

  void save() {
    final brand = brandController.text.trim();
    final capacity = int.tryParse(capacityController.text.trim());
    final cRate = int.tryParse(cRateController.text.trim());

    if (brand.isEmpty || capacity == null || cRate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renseigne marque, capacité et taux C')),
      );
      return;
    }

    final pairId = createPair ? nextPairId() : null;

    final first = Battery(
      id: nextBatteryId(technology),
      technology: technology,
      brand: brand,
      capacity: capacity,
      cells: cells,
      cRate: cRate,
      pairId: pairId,
    );

    if (!createPair) {
      Navigator.pop(context, [first]);
      return;
    }

    final second = Battery(
      id: nextBatteryId(technology),
      technology: technology,
      brand: brand,
      capacity: capacity,
      cells: cells,
      cRate: cRate,
      pairId: pairId,
    );

    Navigator.pop(context, [first, second]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle batterie')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: technology,
            decoration: const InputDecoration(labelText: 'Technologie', border: OutlineInputBorder()),
            items: technologies.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => setState(() => technology = value!),
          ),
          const SizedBox(height: 14),
          TextField(controller: brandController, decoration: const InputDecoration(labelText: 'Marque', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          TextField(controller: capacityController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacité (mAh)', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: cells,
            decoration: const InputDecoration(labelText: 'Nombre de cellules', border: OutlineInputBorder()),
            items: cellOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => setState(() => cells = value!),
          ),
          const SizedBox(height: 14),
          TextField(controller: cRateController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Taux de décharge (C)', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          SwitchListTile(
            value: createPair,
            title: const Text('Créer une paire'),
            subtitle: const Text('Génère deux batteries identiques'),
            onChanged: (value) => setState(() => createPair = value),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('Enregistrer')),
        ],
      ),
    );
  }
}
