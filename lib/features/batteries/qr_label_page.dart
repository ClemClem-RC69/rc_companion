import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/battery.dart';

class QrLabelPage extends StatelessWidget {
  const QrLabelPage({super.key, required this.battery});

  final Battery battery;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Étiquette QR Code')),
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(data: battery.id, version: QrVersions.auto, size: 220),
                const SizedBox(height: 16),
                Text(battery.id, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                if (battery.pairId != null) ...[
                  const SizedBox(height: 8),
                  Text(battery.pairId!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ],
                const SizedBox(height: 12),
                Text('${battery.cells} • ${battery.capacity} mAh • ${battery.cRate}C', style: const TextStyle(fontSize: 18)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
