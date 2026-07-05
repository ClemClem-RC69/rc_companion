import 'package:flutter/material.dart';

void main() {
  runApp(const RCCompanionApp());
}

class RCCompanionApp extends StatelessWidget {
  const RCCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RC Companion',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.red),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.red,
        brightness: Brightness.dark,
      ),
      home: const DashboardPage(),
    );
  }
}

/* =========================
   DONNÉES
========================= */

class RcModel {
  RcModel({
    required this.name,
    required this.brand,
    required this.category,
    required this.motorization,
    required this.scale,
    required this.batteryCount,
    required this.maxBatteryCells,
    required this.batteryTechnology,
    required this.batterySetup,
  });

  final String name;
  final String brand;
  final String category;
  final String motorization;
  final String scale;
  final int batteryCount;
  final String maxBatteryCells;
  final String batteryTechnology;
  final String batterySetup;

  String get powerLabel {
    if (motorization == 'Thermique') return 'Thermique';
    if (batteryCount == 1) {
      return '$batteryTechnology • 1 × $maxBatteryCells max';
    }
    return '$batteryTechnology • 2 × $maxBatteryCells max $batterySetup';
  }
}

class Battery {
  Battery({
    required this.id,
    required this.technology,
    required this.brand,
    required this.capacity,
    required this.cells,
    required this.cRate,
    this.pairId,
  });

  final String id;
  final String technology;
  final String brand;
  final int capacity;
  final String cells;
  final int cRate;
  final String? pairId;
}

final List<RcModel> rcModels = [];
final List<Battery> batteries = [];

int batteryCounter = 1;
int pairCounter = 1;

/* =========================
   ACCUEIL
========================= */

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  void openSimplePage(BuildContext context, String title, String message) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SimplePage(title: title, message: message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RC Companion'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Mon garage RC',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          HomeCard(
            icon: Icons.directions_car,
            title: 'Mes modèles',
            subtitle: 'Voitures, bateaux, avions, drones et hélicos',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ModelsPage()),
            ),
          ),
          HomeCard(
            icon: Icons.battery_charging_full,
            title: 'Mes batteries',
            subtitle: 'Technologie, capacité, C, QR Code et paires',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BatteriesPage()),
            ),
          ),
          HomeCard(
            icon: Icons.route,
            title: 'Nouvelle session',
            subtitle: 'Enregistrer une sortie en moins de 30 secondes',
            onTap: () => openSimplePage(
              context,
              'Nouvelle session',
              'Bientôt : choix du modèle + scan QR batteries',
            ),
          ),
          HomeCard(
            icon: Icons.build,
            title: 'Entretiens',
            subtitle: 'Réparations, réglages et modifications',
            onTap: () => openSimplePage(
              context,
              'Entretiens',
              'Historique des entretiens',
            ),
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
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class SimplePage extends StatelessWidget {
  const SimplePage({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text(message, style: const TextStyle(fontSize: 22))),
    );
  }
}

/* =========================
   MODÈLES RC
========================= */

class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key});

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  void addModel() async {
    final newModel = await Navigator.push<RcModel>(
      context,
      MaterialPageRoute(builder: (_) => const AddModelPage()),
    );

    if (newModel != null) {
      setState(() {
        rcModels.add(newModel);
      });
    }
  }

  IconData iconForCategory(String category) {
    switch (category) {
      case 'Bateau':
        return Icons.sailing;
      case 'Avion':
        return Icons.flight;
      case 'Hélicoptère':
        return Icons.air;
      case 'Drone':
        return Icons.radar;
      default:
        return Icons.directions_car;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes modèles'),
      ),
      body: rcModels.isEmpty
          ? const Center(
              child: Text(
                'Aucun modèle pour le moment',
                style: TextStyle(fontSize: 22),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rcModels.length,
              itemBuilder: (context, index) {
                final model = rcModels[index];

                return Card(
                  child: ListTile(
                    leading: Icon(iconForCategory(model.category), size: 36),
                    title: Text(model.name),
                    subtitle: Text(
                      '${model.brand} • ${model.category} • ${model.scale}\n${model.powerLabel}',
                    ),
                    isThreeLine: true,
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
  String batteryTechnology = 'LiPo';
  String maxBatteryCells = '4S';
  int batteryCount = 1;
  String batterySetup = 'en série';

  final categories = ['Voiture', 'Bateau', 'Avion', 'Hélicoptère', 'Drone'];
  final motorisations = ['Électrique', 'Thermique'];
  final scales = [
    '1/24',
    '1/18',
    '1/16',
    '1/14',
    '1/12',
    '1/10',
    '1/8',
    '1/7',
    '1/6',
    '1/5',
    'Autre',
  ];
  final technologies = ['LiPo', 'LiHV', 'Li-Ion', 'LiFe', 'NiMH', 'NiCd'];
  final cellOptions = ['1S', '2S', '3S', '4S', '5S', '6S', '8S', '10S', '12S'];
  final setupOptions = ['en série', 'en parallèle'];

  void saveModel() {
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
        maxBatteryCells: motorization == 'Électrique' ? maxBatteryCells : '',
        batteryTechnology:
            motorization == 'Électrique' ? batteryTechnology : '',
        batterySetup: motorization == 'Électrique' ? batterySetup : '',
      ),
    );
  }

  Widget electricSection() {
    if (motorization == 'Thermique') {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: batteryTechnology,
          decoration: const InputDecoration(
            labelText: 'Technologie batterie',
            border: OutlineInputBorder(),
          ),
          items: technologies.map((item) {
            return DropdownMenuItem(value: item, child: Text(item));
          }).toList(),
          onChanged: (value) => setState(() => batteryTechnology = value!),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          value: batteryCount,
          decoration: const InputDecoration(
            labelText: 'Nombre de batteries',
            border: OutlineInputBorder(),
          ),
          items: [1, 2].map((item) {
            return DropdownMenuItem(
              value: item,
              child: Text('$item batterie(s)'),
            );
          }).toList(),
          onChanged: (value) => setState(() => batteryCount = value!),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: maxBatteryCells,
          decoration: const InputDecoration(
            labelText: 'Type maximum par batterie',
            border: OutlineInputBorder(),
          ),
          items: cellOptions.map((item) {
            return DropdownMenuItem(value: item, child: Text(item));
          }).toList(),
          onChanged: (value) => setState(() => maxBatteryCells = value!),
        ),
        const SizedBox(height: 14),
        if (batteryCount == 2)
          DropdownButtonFormField<String>(
            value: batterySetup,
            decoration: const InputDecoration(
              labelText: 'Montage',
              border: OutlineInputBorder(),
            ),
            items: setupOptions.map((item) {
              return DropdownMenuItem(value: item, child: Text(item));
            }).toList(),
            onChanged: (value) => setState(() => batterySetup = value!),
          ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              batteryCount == 1
                  ? 'Alimentation : $batteryTechnology • 1 × $maxBatteryCells max'
                  : 'Alimentation : $batteryTechnology • 2 × $maxBatteryCells max $batterySetup',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveau modèle'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Nom du modèle',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: brandController,
            decoration: const InputDecoration(
              labelText: 'Marque',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: category,
            decoration: const InputDecoration(
              labelText: 'Catégorie',
              border: OutlineInputBorder(),
            ),
            items: categories.map((item) {
              return DropdownMenuItem(value: item, child: Text(item));
            }).toList(),
            onChanged: (value) => setState(() => category = value!),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: motorization,
            decoration: const InputDecoration(
              labelText: 'Motorisation',
              border: OutlineInputBorder(),
            ),
            items: motorisations.map((item) {
              return DropdownMenuItem(value: item, child: Text(item));
            }).toList(),
            onChanged: (value) => setState(() => motorization = value!),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: scale,
            decoration: const InputDecoration(
              labelText: 'Échelle',
              border: OutlineInputBorder(),
            ),
            items: scales.map((item) {
              return DropdownMenuItem(value: item, child: Text(item));
            }).toList(),
            onChanged: (value) => setState(() => scale = value!),
          ),
          const SizedBox(height: 14),
          electricSection(),
          FilledButton.icon(
            onPressed: saveModel,
            icon: const Icon(Icons.save),
            label: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

/* =========================
   BATTERIES
========================= */

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
      setState(() {
        batteries.addAll(created);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes batteries'),
      ),
      body: batteries.isEmpty
          ? const Center(
              child: Text(
                'Aucune batterie pour le moment',
                style: TextStyle(fontSize: 22),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: batteries.length,
              itemBuilder: (context, index) {
                final battery = batteries[index];

                return Card(
                  child: ListTile(
                    leading:
                        const Icon(Icons.battery_charging_full, size: 36),
                    title: Text(battery.id),
                    subtitle: Text(
                      '${battery.technology} • ${battery.brand} • ${battery.cells} • ${battery.capacity} mAh • ${battery.cRate}C'
                      '${battery.pairId == null ? '' : ' • Paire ${battery.pairId}'}',
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BatteryDetailPage(battery: battery),
                      ),
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
  final cellOptions = [
    '1S',
    '2S',
    '3S',
    '4S',
    '5S',
    '6S',
    '8S',
    '10S',
    '12S'
  ];

  String nextBatteryId(String technology) {
    final prefix = technology.toUpperCase().replaceAll('-', '').replaceAll(' ', '');
    final number = batteryCounter.toString().padLeft(3, '0');
    batteryCounter++;

    return '$prefix-$number';
  }

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

    final pairId =
        createPair ? 'P${pairCounter.toString().padLeft(3, '0')}' : null;
    if (createPair) pairCounter++;

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
      appBar: AppBar(
        title: const Text('Nouvelle batterie'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: technology,
            decoration: const InputDecoration(
              labelText: 'Technologie',
              border: OutlineInputBorder(),
            ),
            items: technologies.map((item) {
              return DropdownMenuItem(value: item, child: Text(item));
            }).toList(),
            onChanged: (value) => setState(() => technology = value!),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: brandController,
            decoration: const InputDecoration(
              labelText: 'Marque',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: capacityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Capacité (mAh)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: cells,
            decoration: const InputDecoration(
              labelText: 'Nombre de cellules',
              border: OutlineInputBorder(),
            ),
            items: cellOptions.map((item) {
              return DropdownMenuItem(value: item, child: Text(item));
            }).toList(),
            onChanged: (value) => setState(() => cells = value!),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: cRateController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Taux de décharge (C)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            value: createPair,
            title: const Text('Créer une paire'),
            subtitle:
                const Text('Génère automatiquement deux batteries identiques'),
            onChanged: (value) => setState(() => createPair = value),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: save,
            icon: const Icon(Icons.save),
            label: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

class BatteryDetailPage extends StatelessWidget {
  const BatteryDetailPage({
    super.key,
    required this.battery,
  });

  final Battery battery;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(battery.id),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.qr_code_2, size: 42),
              title: Text(battery.id),
              subtitle: Text(
                battery.pairId == null
                    ? 'Batterie seule'
                    : 'Paire ${battery.pairId}',
              ),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Technologie'),
              trailing: Text(battery.technology),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Marque'),
              trailing: Text(battery.brand),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Capacité'),
              trailing: Text('${battery.capacity} mAh'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Cellules'),
              trailing: Text(battery.cells),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Taux C'),
              trailing: Text('${battery.cRate}C'),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.print),
            label: const Text('Préparer étiquette QR Code'),
          ),
        ],
      ),
    );
  }
}
