import 'package:flutter/material.dart';

import '../../models/battery.dart';
import 'qr_label_page.dart';

class BatteryDetailPage extends StatelessWidget {
  const BatteryDetailPage({super.key, required this.battery});

  final Battery battery;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(battery.id)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.qr_code_2, size: 42),
              title: Text(battery.id),
              subtitle: Text(battery.pairId == null ? 'Batterie seule' : 'Paire ${battery.pairId}'),
            ),
          ),
          info('Technologie', battery.technology),
          info('Marque', battery.brand),
          info('Capacité', '${battery.capacity} mAh'),
          info('Cellules', battery.cells),
          info('Taux C', '${battery.cRate}C'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => QrLabelPage(battery: battery)),
              );
            },
            icon: const Icon(Icons.print),
            label: const Text('Préparer étiquette QR Code'),
          ),
        ],
      ),
    );
  }

  Widget info(String title, String value) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(value),
      ),
    );
  }
}
