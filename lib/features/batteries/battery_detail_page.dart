import 'package:flutter/material.dart';

import '../../models/battery.dart';
import '../../services/battery_service.dart';
import 'qr_label_page.dart';

class BatteryDetailPage extends StatefulWidget {
  const BatteryDetailPage({
    super.key,
    required this.battery,
  });

  final Battery battery;

  @override
  State<BatteryDetailPage> createState() => _BatteryDetailPageState();
}

class _BatteryDetailPageState extends State<BatteryDetailPage> {
  late Battery battery;

  @override
  void initState() {
    super.initState();
    battery = widget.battery;
  }

  Future<void> _editBattery() async {
    final formKey = GlobalKey<FormState>();
    final brandController = TextEditingController(text: battery.brand);
    final capacityController = TextEditingController(
      text: battery.capacity.toString(),
    );
    final cRateController = TextEditingController(
      text: battery.cRate.toString(),
    );
    final notesController = TextEditingController(
      text: battery.notes ?? '',
    );

    var cells = battery.cells;
    var status = battery.status;
    var isSaving = false;

    final result =
    await showDialog<(Battery, bool)>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> save() async {
              if (!formKey.currentState!.validate() || isSaving) {
                return;
              }

              setDialogState(() {
                isSaving = true;
              });

              try {
               final newBrand = brandController.text.trim();
final newCapacity =
    int.parse(capacityController.text.trim());
final newCRate =
    int.parse(cRateController.text.trim());

final pairMustBeDissolved =
    battery.isPaired &&
    (
      newBrand != battery.brand ||
      newCapacity != battery.capacity ||
      cells != battery.cells ||
      newCRate != battery.cRate
    );

if (pairMustBeDissolved &&
    battery.pairId != null) {
  await BatteryService.dissolvePair(
    battery.pairId!,
  );
}

final editedBattery = battery.copyWith(
  brand: newBrand,
  capacity: newCapacity,
  cRate: newCRate,
  cells: cells,
  status: status,
  notes: notesController.text.trim().isEmpty
      ? null
      : notesController.text.trim(),
  removePair: pairMustBeDissolved,
);

await BatteryService.updateBattery(editedBattery);

if (!dialogContext.mounted) {
  return;
}

Navigator.pop(
  dialogContext,
  (
    editedBattery,
    pairMustBeDissolved,
  ),
);
              } catch (error) {
                if (!dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  isSaving = false;
                });

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Modification impossible : $error',
                    ),
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('Modifier la batterie'),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          initialValue: battery.id,
                          enabled: false,
                          decoration: const InputDecoration(
                            labelText: 'Identifiant',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          initialValue: battery.technology,
                          enabled: false,
                          decoration: const InputDecoration(
                            labelText: 'Technologie',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: brandController,
                          enabled: !isSaving,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Marque',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Renseigne la marque';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: capacityController,
                          enabled: !isSaving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Capacité (mAh)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final number = int.tryParse(
                              value?.trim() ?? '',
                            );

                            if (number == null || number <= 0) {
                              return 'Renseigne une capacité valide';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: cells,
                          decoration: const InputDecoration(
                            labelText: 'Nombre de cellules',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            '1S',
                            '2S',
                            '3S',
                            '4S',
                            '5S',
                            '6S',
                          ]
                              .map(
                                (value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setDialogState(() {
                                      cells = value;
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: cRateController,
                          enabled: !isSaving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Taux de décharge (C)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final number = int.tryParse(
                              value?.trim() ?? '',
                            );

                            if (number == null || number <= 0) {
                              return 'Renseigne un taux C valide';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: status,
                          decoration: const InputDecoration(
                            labelText: 'Statut',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            'Active',
                            'Stockage',
                            'À surveiller',
                            'HS',
                            'Retirée',
                          ]
                              .map(
                                (value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setDialogState(() {
                                      status = value;
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: notesController,
                          enabled: !isSaving,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Notes',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Annuler'),
                ),
                FilledButton.icon(
                  onPressed: isSaving ? null : save,
                  icon: isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    isSaving ? 'Enregistrement...' : 'Enregistrer',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    brandController.dispose();
    capacityController.dispose();
    cRateController.dispose();
    notesController.dispose();

    if (result == null || !mounted) {
  return;
}

final updatedBattery = result.$1;
final pairWasDissolved = result.$2;

setState(() {
  battery = updatedBattery;
});

ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(
      pairWasDissolved
          ? 'PAIRE ANNULÉE — BATTERIES INCOMPATIBLES'
          : 'Batterie mise à jour',
    ),
  ),
);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(battery.id),
        actions: [
          IconButton(
            onPressed: _editBattery,
            tooltip: 'Modifier',
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.qr_code_2, size: 42),
              title: Text(battery.id),
              subtitle: Text(
                battery.isPaired
                    ? 'Paire ${battery.pairId}'
                    : 'Batterie seule',
              ),
            ),
          ),
          _info('Technologie', battery.technology),
          _info('Marque', battery.brand),
          _info('Capacité', '${battery.capacity} mAh'),
          _info('Cellules', battery.cells),
          _info('Taux C', '${battery.cRate}C'),
          _info('Statut', battery.status),
          if (battery.notes != null && battery.notes!.trim().isNotEmpty)
            _info('Notes', battery.notes!),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => QrLabelPage(battery: battery),
                ),
              );
            },
            icon: const Icon(Icons.print),
            label: const Text('Préparer étiquette QR Code'),
          ),
        ],
      ),
    );
  }

  Widget _info(String title, String value) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            value,
            textAlign: TextAlign.end,
          ),
        ),
      ),
    );
  }
}
