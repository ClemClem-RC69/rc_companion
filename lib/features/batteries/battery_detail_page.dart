import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/battery.dart';
import '../../models/battery_measurement.dart';
import '../../services/battery_service.dart';
import 'qr_label_page.dart';

class BatteryDetailPage extends StatefulWidget {
  const BatteryDetailPage({
    super.key,
    required this.battery,
    this.startAfterChargeState,
  });

  final Battery battery;
  final BatteryChargeState? startAfterChargeState;

  @override
  State<BatteryDetailPage> createState() => _BatteryDetailPageState();
}

class _BatteryDetailPageState extends State<BatteryDetailPage>
    with SingleTickerProviderStateMixin {
  late Battery battery;
  late final TabController _tabController;

  List<BatteryMeasurement> _measurements = [];
  bool _isLoadingMeasurements = true;
  String? _measurementsError;

  @override
  void initState() {
    super.initState();
    battery = widget.battery;
    _tabController = TabController(length: 3, vsync: this);
    _loadMeasurements();

    final initialState = widget.startAfterChargeState;
    if (initialState != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _addMeasurement(
            BatteryMeasurement.afterChargeType,
            afterChargeState: initialState,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int get _cellCount {
    return int.tryParse(battery.cells.replaceAll('S', '')) ?? 1;
  }

  String _formatDecimal(double value, {int maxDecimals = 3}) {
    var text = value.toStringAsFixed(maxDecimals);

    while (text.contains('.') && text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }

    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }

    return text.replaceAll('.', ',');
  }

  Future<void> _loadMeasurements() async {
    setState(() {
      _isLoadingMeasurements = true;
      _measurementsError = null;
    });

    try {
      final measurements = await BatteryService.getBatteryMeasurements(
        battery.id,
      );

      if (!mounted) {
        return;
      }

      final cachedBatteries = await BatteryService.getCachedBatteries();
      Battery? refreshedBattery;

      for (final cachedBattery in cachedBatteries) {
        if (cachedBattery.id == battery.id) {
          refreshedBattery = cachedBattery;
          break;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _measurements = measurements;
        if (refreshedBattery != null) {
          battery = refreshedBattery;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _measurementsError = 'Impossible de charger les mesures : $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMeasurements = false;
        });
      }
    }
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
    final notesController = TextEditingController(text: battery.notes ?? '');

    var cells = battery.cells;
    var status = battery.status;
    var isSaving = false;

    final result = await showDialog<(Battery, bool)>(
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
                final newCapacity = int.parse(capacityController.text.trim());
                final newCRate = int.parse(cRateController.text.trim());

                final pairMustBeDissolved =
                    battery.isPaired &&
                    (newBrand != battery.brand ||
                        newCapacity != battery.capacity ||
                        cells != battery.cells ||
                        newCRate != battery.cRate);

                if (pairMustBeDissolved && battery.pairId != null) {
                  await BatteryService.dissolvePair(battery.pairId!);
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

                Navigator.pop(dialogContext, (
                  editedBattery,
                  pairMustBeDissolved,
                ));
              } catch (error) {
                if (!dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  isSaving = false;
                });

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('Modification impossible : $error')),
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
                            final number = int.tryParse(value?.trim() ?? '');

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
                          items: const ['1S', '2S', '3S', '4S', '5S', '6S']
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
                            final number = int.tryParse(value?.trim() ?? '');

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
                          items:
                              const [
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(isSaving ? 'Enregistrement...' : 'Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) {
      brandController.dispose();
      capacityController.dispose();
      cRateController.dispose();
      notesController.dispose();
      return;
    }

    await Future.delayed(const Duration(milliseconds: 100));

    brandController.dispose();
    capacityController.dispose();
    cRateController.dispose();
    notesController.dispose();

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

  BatteryChargeState _afterChargeStateFromMeasurement(
    BatteryMeasurement measurement,
  ) {
    final notes = measurement.notes ?? '';

    if (notes.split('|').any((part) => part.trim() == 'charge_state:storage')) {
      return BatteryChargeState.storage;
    }

    return measurement.chargePercent >= 95
        ? BatteryChargeState.charged
        : BatteryChargeState.partial;
  }

  Future<BatteryChargeState?> _chooseAfterChargeState() {
    return showDialog<BatteryChargeState>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('État après charge'),
        content: const Text(
          'Quel état souhaites-tu attribuer à cette batterie ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.pop(dialogContext, BatteryChargeState.storage),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Storage'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(dialogContext, BatteryChargeState.charged),
            icon: const Icon(Icons.battery_charging_full),
            label: const Text('Chargée'),
          ),
        ],
      ),
    );
  }

  Future<void> _startAfterChargeMeasurement() async {
    final selectedState = await _chooseAfterChargeState();

    if (selectedState == null || !mounted) {
      return;
    }

    await _addMeasurement(
      BatteryMeasurement.afterChargeType,
      afterChargeState: selectedState,
    );
  }

  Future<void> _addMeasurement(
    String measurementType, {
    BatteryMeasurement? initialMeasurement,
    BatteryChargeState? afterChargeState,
  }) async {
    final formKey = GlobalKey<FormState>();
    final usesResistance = measurementType != BatteryMeasurement.endOfRunType;

    final chargeController = TextEditingController(
      text: initialMeasurement?.chargePercent.toString() ?? '',
    );
    final temperatureController = TextEditingController(
      text: initialMeasurement?.batteryTemperature == null
          ? ''
          : _formatDecimal(initialMeasurement!.batteryTemperature!),
    );
    final voltageControllers = List.generate(
      _cellCount,
      (index) => TextEditingController(
        text:
            initialMeasurement != null &&
                index < initialMeasurement.cellVoltages.length
            ? _formatDecimal(initialMeasurement.cellVoltages[index])
            : '',
      ),
    );
    final resistanceControllers = usesResistance
        ? List.generate(
            _cellCount,
            (index) => TextEditingController(
              text:
                  initialMeasurement != null &&
                      index < initialMeasurement.cellInternalResistances.length
                  ? _formatDecimal(
                      initialMeasurement.cellInternalResistances[index],
                      maxDecimals: 2,
                    )
                  : '',
            ),
          )
        : <TextEditingController>[];

    var isSaving = false;

    final measurement = await showDialog<BatteryMeasurement>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final isCompactMeasurementDialog =
                MediaQuery.sizeOf(dialogContext).width < 700;

            double? parseDecimal(String value) {
              return double.tryParse(value.trim().replaceAll(',', '.'));
            }

            List<double> enteredVoltages() {
              return voltageControllers
                  .map((controller) => parseDecimal(controller.text))
                  .whereType<double>()
                  .toList(growable: false);
            }

            double enteredTotalVoltage() {
              return enteredVoltages().fold<double>(
                0,
                (total, voltage) => total + voltage,
              );
            }

            double enteredMaximumDifference() {
              final values = enteredVoltages();

              if (values.length < 2) {
                return 0;
              }

              final minimum = values.reduce(
                (current, next) => current < next ? current : next,
              );
              final maximum = values.reduce(
                (current, next) => current > next ? current : next,
              );

              return maximum - minimum;
            }

            String? validatePositiveDecimal(String? value, String label) {
              final parsed = parseDecimal(value ?? '');

              if (parsed == null || parsed <= 0) {
                return 'Valeur $label invalide';
              }

              return null;
            }

            String? validateNonNegativeDecimal(String? value, String label) {
              final parsed = parseDecimal(value ?? '');

              if (parsed == null || parsed < 0) {
                return 'Valeur $label invalide';
              }

              return null;
            }

            Future<void> save() async {
              if (!formKey.currentState!.validate() || isSaving) {
                return;
              }

              setDialogState(() {
                isSaving = true;
              });

              try {
                final cellVoltages = voltageControllers
                    .map((controller) => parseDecimal(controller.text)!)
                    .toList();

                final internalResistances = usesResistance
                    ? resistanceControllers
                          .map((controller) => parseDecimal(controller.text)!)
                          .toList()
                    : const <double>[];

                final newMeasurement = BatteryMeasurement(
                  id: initialMeasurement?.id,
                  batteryCode: battery.id,
                  measuredAt: initialMeasurement?.measuredAt ?? DateTime.now(),
                  measurementType: measurementType,
                  chargePercent: int.parse(chargeController.text.trim()),
                  cellVoltages: cellVoltages,
                  cellInternalResistances: internalResistances,
                  batteryTemperature: usesResistance
                      ? null
                      : parseDecimal(temperatureController.text),
                  notes: measurementType == BatteryMeasurement.afterChargeType
                      ? BatteryService.withAfterChargeStateNote(
                          initialMeasurement?.notes,
                          afterChargeState ?? BatteryChargeState.charged,
                        )
                      : initialMeasurement?.notes,
                );

                late final BatteryMeasurement savedMeasurement;

                if (initialMeasurement != null) {
                  if (measurementType == BatteryMeasurement.referenceType) {
                    savedMeasurement =
                        await BatteryService.saveReferenceMeasurement(
                          newMeasurement,
                        ).timeout(const Duration(seconds: 15));
                  } else {
                    savedMeasurement =
                        await BatteryService.updateBatteryMeasurement(
                          newMeasurement,
                        ).timeout(const Duration(seconds: 15));
                  }
                } else if (measurementType ==
                    BatteryMeasurement.referenceType) {
                  savedMeasurement =
                      await BatteryService.saveReferenceMeasurement(
                        newMeasurement,
                      ).timeout(const Duration(seconds: 15));
                } else {
                  savedMeasurement =
                      await BatteryService.createBatteryMeasurement(
                        newMeasurement,
                      ).timeout(const Duration(seconds: 15));
                }

                if (!dialogContext.mounted) {
                  return;
                }

                Navigator.pop(dialogContext, savedMeasurement);
              } on TimeoutException {
                if (!dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  isSaving = false;
                });

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'La sauvegarde met trop de temps. Vérifie la connexion puis réessaie.',
                    ),
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
                  SnackBar(content: Text('Enregistrement impossible : $error')),
                );
              }
            }

            return AlertDialog(
              scrollable: true,
              title: Text(
                initialMeasurement == null
                    ? measurementType
                    : 'Modifier — $measurementType',
              ),
              content: SizedBox(
                width: isCompactMeasurementDialog
                    ? double.maxFinite
                    : (usesResistance ? 720 : 610),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Batterie ${battery.id} • ${battery.technology} '
                        '• ${battery.capacity} mAh • ${battery.cells}',
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final fieldWidth = isCompactMeasurementDialog
                              ? (constraints.maxWidth - 12) / 2
                              : null;

                          Widget sizedField(Widget child) {
                            if (fieldWidth != null) {
                              return SizedBox(width: fieldWidth, child: child);
                            }
                            return Expanded(child: child);
                          }

                          final fields = <Widget>[
                            sizedField(
                              TextFormField(
                                controller: chargeController,
                                enabled: !isSaving,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: usesResistance
                                      ? 'Niveau de charge'
                                      : 'Capacité restante',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  border: const OutlineInputBorder(),
                                  suffixText: '%',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                ),
                                validator: (value) {
                                  final percent = int.tryParse(
                                    value?.trim() ?? '',
                                  );
                                  if (percent == null ||
                                      percent < 0 ||
                                      percent > 100) {
                                    return 'Pourcentage entre 0 et 100';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            if (!usesResistance)
                              sizedField(
                                TextFormField(
                                  controller: temperatureController,
                                  enabled: !isSaving,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Température',
                                    suffixText: '°C',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 14,
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return null;
                                    }
                                    return parseDecimal(value) == null
                                        ? 'Température invalide'
                                        : null;
                                  },
                                ),
                              ),
                            sizedField(
                              InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Tension totale',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                ),
                                child: Text(
                                  '${_formatDecimal(enteredTotalVoltage())} V',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            sizedField(
                              InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Écart cellules',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                ),
                                child: Text(
                                  '${_formatDecimal(enteredMaximumDifference())} V',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ];

                          if (isCompactMeasurementDialog) {
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: fields,
                            );
                          }

                          return Row(
                            children: [
                              for (
                                var index = 0;
                                index < fields.length;
                                index++
                              ) ...[
                                if (index > 0) const SizedBox(width: 12),
                                fields[index],
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          SizedBox(
                            width: isCompactMeasurementDialog ? 64 : 90,
                            child: const Text(
                              'Cellule',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const Expanded(
                            child: Text(
                              'Tension',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (usesResistance) ...[
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Résistance interne',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (var index = 0; index < _cellCount; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: isCompactMeasurementDialog ? 64 : 90,
                                child: Text(
                                  isCompactMeasurementDialog
                                      ? 'C${index + 1}'
                                      : 'Cellule ${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: TextFormField(
                                  controller: voltageControllers[index],
                                  enabled: !isSaving,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    hintText: '0,000',
                                    suffixText: 'V',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 14,
                                    ),
                                  ),
                                  onChanged: (_) => setDialogState(() {}),
                                  validator: (value) => validatePositiveDecimal(
                                    value,
                                    'de tension',
                                  ),
                                ),
                              ),
                              if (usesResistance) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: resistanceControllers[index],
                                    enabled: !isSaving,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      hintText: '0,0',
                                      suffixText: 'mΩ',
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 14,
                                      ),
                                    ),
                                    validator: (value) =>
                                        validateNonNegativeDecimal(
                                          value,
                                          'de résistance',
                                        ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(isSaving ? 'Enregistrement...' : 'Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (measurement == null || !mounted) {
      chargeController.dispose();
      temperatureController.dispose();

      for (final controller in voltageControllers) {
        controller.dispose();
      }

      for (final controller in resistanceControllers) {
        controller.dispose();
      }

      return;
    }

    await Future.delayed(const Duration(milliseconds: 100));

    chargeController.dispose();
    temperatureController.dispose();

    for (final controller in voltageControllers) {
      controller.dispose();
    }

    for (final controller in resistanceControllers) {
      controller.dispose();
    }

    await _loadMeasurements();

    if (!mounted) {
      return;
    }

    if (initialMeasurement != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Relevé modifié.')));
    } else if (measurement.hasInternalResistance) {
      _tabController.animateTo(1);
      await _showMeasurementResult(measurement);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relevé fin de roulage enregistré.')),
      );
    }
  }

  Future<void> _showMeasurementResult(BatteryMeasurement measurement) async {
    final analysis = _analyzeMeasurement(measurement);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                analysis.hasCritical
                    ? Icons.error
                    : analysis.hasWarning
                    ? Icons.warning_amber
                    : Icons.check_circle,
                color: analysis.hasCritical
                    ? Theme.of(context).colorScheme.error
                    : analysis.hasWarning
                    ? Colors.orange
                    : Colors.green,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  analysis.hasCritical
                      ? 'Relevé enregistré — ALERTE'
                      : analysis.hasWarning
                      ? 'Relevé enregistré — À surveiller'
                      : 'Relevé enregistré — Bon état',
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _resultLine(
                    'Tension totale',
                    '${_formatDecimal(measurement.totalVoltage)} V',
                  ),
                  _resultLine(
                    'Écart maximal de tension',
                    '${_formatDecimal(measurement.maximumVoltageDifference)} V',
                  ),
                  _resultLine(
                    'Écart maximal de RI',
                    '${_formatDecimal(measurement.maximumInternalResistanceDifference, maxDecimals: 2)} mΩ',
                  ),
                  const Divider(height: 28),
                  Text(
                    'Analyse des cellules',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...analysis.cellMessages.map(
                    (message) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(message),
                    ),
                  ),
                  if (analysis.globalMessages.isNotEmpty) ...[
                    const Divider(height: 28),
                    Text(
                      'Analyse globale',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...analysis.globalMessages.map(
                      (message) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(message),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Ces alertes sont des repères de suivi. '
                    'En cas de gonflement, choc, fuite, odeur ou '
                    'échauffement anormal, retire la batterie du service.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  _MeasurementAnalysis _analyzeMeasurement(BatteryMeasurement measurement) {
    final health = BatteryService.calculateBatteryHealth(_measurements);

    final latest = health.latestAfterCharge ?? measurement;

    final voltageSpread = latest.maximumVoltageDifference;

    final resistanceSpread = latest.maximumInternalResistanceDifference;

    final evolution = health.resistanceEvolutionPercent;

    final level = switch (health.level) {
      BatteryHealthLevel.notEvaluated => _BatteryHealthLevel.notEvaluated,
      BatteryHealthLevel.good => _BatteryHealthLevel.good,
      BatteryHealthLevel.warning => _BatteryHealthLevel.warning,
      BatteryHealthLevel.hs => _BatteryHealthLevel.hs,
    };

    return _MeasurementAnalysis(
      level: level,
      voltageSpread: voltageSpread,
      voltageLabel: voltageSpread <= 0.050
          ? 'Correct'
          : voltageSpread <= 0.100
          ? 'À surveiller'
          : 'Critique',
      resistanceSpread: resistanceSpread,
      resistanceLabel: resistanceSpread <= 5.0
          ? 'Correct'
          : resistanceSpread <= 10.0
          ? 'À surveiller'
          : 'Critique',
      resistanceEvolutionPercent: evolution,
      evolutionLabel: evolution == null
          ? 'Référence absente'
          : evolution <= 25.0
          ? 'Normale'
          : evolution <= 100.0
          ? 'À surveiller'
          : 'Critique',
      cellMessages: health.reasons,
      globalMessages: [
        'Calcul basé sur ${health.afterChargeCount} relevé(s) après charge.',
        'Les relevés de fin de roulage ne sont pas utilisés pour déterminer la santé.',
      ],
    );
  }

  _ResistanceThresholds _internalResistanceThresholds() {
    final capacityAh = battery.capacity / 1000;
    final safeCapacityAh = capacityAh <= 0 ? 1.0 : capacityAh;

    final technology = battery.technology
        .toLowerCase()
        .replaceAll('-', '')
        .replaceAll(' ', '');

    late final double warningFactor;
    late final double criticalFactor;

    switch (technology) {
      case 'lipo':
      case 'lihv':
        warningFactor = 30;
        criticalFactor = 50;
      case 'liion':
        warningFactor = 60;
        criticalFactor = 100;
      case 'life':
        warningFactor = 40;
        criticalFactor = 65;
      case 'nimh':
        warningFactor = 90;
        criticalFactor = 150;
      case 'nicd':
        warningFactor = 80;
        criticalFactor = 130;
      default:
        warningFactor = 50;
        criticalFactor = 90;
    }

    return _ResistanceThresholds(
      warning: warningFactor / safeCapacityAh,
      critical: criticalFactor / safeCapacityAh,
    );
  }

  _VoltageSpreadThresholds _voltageSpreadThresholds() {
    final technology = battery.technology
        .toLowerCase()
        .replaceAll('-', '')
        .replaceAll(' ', '');

    switch (technology) {
      case 'lipo':
      case 'lihv':
      case 'liion':
      case 'life':
        return const _VoltageSpreadThresholds(warning: 0.030, critical: 0.050);
      default:
        return const _VoltageSpreadThresholds(warning: 0.050, critical: 0.100);
    }
  }

  Future<void> _deleteMeasurement(BatteryMeasurement measurement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer ce relevé ?'),
          content: const Text('Cette action est irréversible.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await BatteryService.deleteBatteryMeasurement(measurement);
      await _loadMeasurements();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Relevé supprimé')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Suppression impossible : $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Batterie'),
        actions: [
          IconButton(
            onPressed: _editBattery,
            tooltip: 'Modifier',
            icon: const Icon(Icons.edit),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.add_chart), text: 'Mesures'),
            Tab(
              icon: Icon(Icons.monitor_heart_outlined),
              text: 'État de la batterie',
            ),
            Tab(icon: Icon(Icons.qr_code_2), text: 'QR Code'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildMeasurementsTab(), _buildHealthTab(), _buildQrTab()],
      ),
    );
  }

  BatteryMeasurement? get _latestHealthMeasurement {
    for (final measurement in _measurements) {
      if ((measurement.isAfterCharge || measurement.isReference) &&
          measurement.hasInternalResistance) {
        return measurement;
      }
    }
    return null;
  }

  _MeasurementAnalysis? get _latestAnalysis {
    final measurement = _latestHealthMeasurement;
    return measurement == null ? null : _analyzeMeasurement(measurement);
  }

  String get _healthLabel {
    final analysis = _latestAnalysis;

    return analysis?.label ?? 'Non évaluée';
  }

  Color _healthBackgroundColor(BuildContext context) {
    final analysis = _latestAnalysis;

    return switch (analysis?.level) {
      null || _BatteryHealthLevel.notEvaluated => Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest,
      _BatteryHealthLevel.good => Colors.green.shade700,
      _BatteryHealthLevel.warning => Colors.amber.shade800,
      _BatteryHealthLevel.hs => Colors.red.shade800,
    };
  }

  Color _healthForegroundColor(BuildContext context) {
    if (_latestAnalysis == null ||
        _latestAnalysis!.level == _BatteryHealthLevel.notEvaluated) {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }

    return Colors.white;
  }

  Color _chargeStateColor() {
    if (battery.chargeState == BatteryChargeState.storage) {
      return Colors.blue.shade700;
    }

    final percent = battery.chargePercent;

    if (percent == null) {
      return Colors.red.shade700;
    }

    if (percent >= 50) {
      return Colors.green.shade700;
    }

    if (percent > 21) {
      return Colors.orange.shade700;
    }

    return Colors.red.shade700;
  }

  Widget _chargeStateChip() {
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: _chargeStateColor(),
      avatar: const Icon(Icons.battery_std, size: 18, color: Colors.white),
      label: Text(
        battery.chargeDisplayLabel,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _batteryHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.battery_charging_full, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    battery.id,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${battery.technology} • ${battery.brand} • '
                    '${battery.cells} • ${battery.capacity} mAh • '
                    '${battery.cRate}C',
                  ),
                  const SizedBox(height: 3),
                  Text(
                    battery.isPaired
                        ? 'Paire ${battery.pairId}'
                        : 'Batterie seule',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chargeStateChip(),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: _healthBackgroundColor(context),
                        label: Text(
                          _healthLabel,
                          style: TextStyle(
                            color: _healthForegroundColor(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _batteryHeader(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.qr_code_2, size: 80),
                const SizedBox(height: 12),
                const Text(
                  'Étiquette QR Code individuelle',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Le QR Code identifie uniquement cette batterie, '
                  'même lorsqu’elle appartient à une paire.',
                  textAlign: TextAlign.center,
                ),
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
                  label: const Text('Préparer et imprimer l’étiquette'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMeasurementsTab() {
    return RefreshIndicator(
      onRefresh: _loadMeasurements,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _batteryHeader(),
          const SizedBox(height: 16),
          if (!_measurements.any((item) => item.isReference)) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    _addMeasurement(BatteryMeasurement.referenceType),
                icon: const Icon(Icons.straighten_outlined),
                label: const Text('Ajouter le relevé de référence'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _startAfterChargeMeasurement,
                  icon: const Icon(Icons.battery_charging_full),
                  label: const Text('Relevé après charge'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _addMeasurement(BatteryMeasurement.endOfRunType),
                  icon: const Icon(Icons.sports_score),
                  label: const Text('Relevé après roulage'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Les relevés de fin de roulage sont enregistrés '
                'automatiquement. Les résistances internes sont renseignées '
                'uniquement dans le relevé de référence et les relevés après charge.',
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Historique des relevés',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (_isLoadingMeasurements)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_measurementsError != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(_measurementsError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loadMeasurements,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            )
          else if (_measurements.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Aucun relevé enregistré pour cette batterie.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ..._measurements.map(_measurementCard),
        ],
      ),
    );
  }

  Widget _buildHealthTab() {
    if (_isLoadingMeasurements) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_measurementsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_measurementsError!, textAlign: TextAlign.center),
        ),
      );
    }

    if (_latestHealthMeasurement == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _batteryHeader(),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.monitor_heart_outlined, size: 64),
                  SizedBox(height: 12),
                  Text(
                    'ÉTAT NON ÉVALUÉ*',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Ajoute une mesure de référence puis un relevé '
                    'après charge pour évaluer la santé de cette batterie.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final latest = _latestHealthMeasurement!;
    final reference = _measurements.firstWhere(
      (measurement) => measurement.isReference,
      orElse: () => latest,
    );
    final analysis = _analyzeMeasurement(latest);

    final resistanceEvolution = reference.averageInternalResistance == 0
        ? 0.0
        : ((latest.averageInternalResistance -
                      reference.averageInternalResistance) /
                  reference.averageInternalResistance) *
              100;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _batteryHeader(),
        const SizedBox(height: 16),
        Card(
          color: switch (analysis.level) {
            _BatteryHealthLevel.good => Colors.green.shade700,
            _BatteryHealthLevel.warning => Colors.amber.shade800,
            _BatteryHealthLevel.hs => Colors.red.shade800,
            _BatteryHealthLevel.notEvaluated => Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      switch (analysis.level) {
                        _BatteryHealthLevel.good => Icons.check_circle,
                        _BatteryHealthLevel.warning => Icons.warning_amber,
                        _BatteryHealthLevel.hs => Icons.error,
                        _BatteryHealthLevel.notEvaluated => Icons.help_outline,
                      },
                      size: 46,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        analysis.label.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Justification :',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                ...analysis.cellMessages.map(
                  (message) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '• $message',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                ...analysis.globalMessages.map(
                  (message) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '• $message',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Dernière mesure : ${_formatDateTime(latest.measuredAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        _info(
          'Nombre de relevés après charge',
          _measurements
              .where((item) => item.isAfterCharge && item.hasInternalResistance)
              .length
              .toString(),
        ),
        _info(
          'RI moyenne actuelle',
          '${_formatDecimal(latest.averageInternalResistance, maxDecimals: 2)} mΩ',
        ),
        _info(
          'RI moyenne de référence',
          '${_formatDecimal(reference.averageInternalResistance, maxDecimals: 2)} mΩ',
        ),
        _info(
          'Évolution de la RI moyenne',
          '${resistanceEvolution >= 0 ? '+' : ''}'
              '${resistanceEvolution.toStringAsFixed(1)} %',
        ),
        _info(
          'Écart maximal de tension',
          '${_formatDecimal(latest.maximumVoltageDifference)} V',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Analyse historique après charge',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ...analysis.cellMessages.map(
                  (message) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(message),
                  ),
                ),
                const Divider(height: 24),
                ...analysis.globalMessages.map(
                  (message) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(message),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '* Les informations, calculs et alertes affichés par RC Companion '
          'sont fournis à titre indicatif afin d’aider au suivi des batteries. '
          'Ils ne remplacent pas les recommandations du fabricant, la notice '
          'd’utilisation ni un contrôle visuel et technique. L’utilisateur '
          'reste seul responsable de la charge, de l’utilisation, du stockage '
          'et de la mise hors service de ses batteries. RC Companion et son '
          'concepteur ne sauraient être tenus responsables d’un dommage matériel '
          'ou corporel lié à l’utilisation d’une batterie.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
          textAlign: TextAlign.justify,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  String? _modelNameFromMeasurement(BatteryMeasurement measurement) {
    final notes = measurement.notes;

    if (notes == null || notes.isEmpty) {
      return null;
    }

    for (final part in notes.split('|')) {
      if (part.startsWith('model:')) {
        final modelName = part.substring('model:'.length).trim();
        return modelName.isEmpty ? null : modelName;
      }
    }

    return null;
  }

  Color _measurementTypeColor(BatteryMeasurement measurement) {
    if (measurement.isReference) {
      return Colors.purple.shade700;
    }

    if (measurement.isAfterCharge) {
      return Colors.green.shade700;
    }

    if (measurement.isEndOfSession) {
      return Colors.blue.shade700;
    }

    return Colors.orange.shade700;
  }

  IconData _measurementTypeIcon(BatteryMeasurement measurement) {
    if (measurement.isReference) {
      return Icons.straighten_outlined;
    }

    if (measurement.isAfterCharge) {
      return Icons.battery_charging_full;
    }

    if (measurement.isEndOfSession) {
      return Icons.sports_score;
    }

    return Icons.search;
  }

  String _measurementTypeTitle(BatteryMeasurement measurement) {
    return measurement.measurementType.toUpperCase();
  }

  Widget _measurementCard(BatteryMeasurement measurement) {
    final typeColor = _measurementTypeColor(measurement);
    final modelName = _modelNameFromMeasurement(measurement);

    return Card(
      child: ExpansionTile(
        key: PageStorageKey<String>(
          'measurement-${measurement.id ?? measurement.measuredAt.toIso8601String()}',
        ),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: typeColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_measurementTypeIcon(measurement), color: Colors.white),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _measurementTypeTitle(measurement),
                style: TextStyle(
                  color: typeColor,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (measurement.isEndOfSession && modelName != null)
                Text(
                  'Modèle : $modelName',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              Text(_formatDateTime(measurement.measuredAt)),
              const SizedBox(height: 3),
              Text(
                '${measurement.chargePercent}% • '
                '${_formatDecimal(measurement.totalVoltage)} V',
              ),
            ],
          ),
        ),
        controlAffinity: ListTileControlAffinity.trailing,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const SizedBox(height: 8),
          _resultLine('Type de relevé', measurement.measurementType),
          if (measurement.isEndOfSession && modelName != null)
            _resultLine('Modèle utilisé', modelName),
          _resultLine(
            measurement.isEndOfRun ? 'Capacité restante' : 'Niveau de charge',
            '${measurement.chargePercent}%',
          ),
          if (measurement.isEndOfRun && measurement.batteryTemperature != null)
            _resultLine(
              'Température',
              '${_formatDecimal(measurement.batteryTemperature!)} °C',
            ),
          _resultLine(
            'Tension totale',
            '${_formatDecimal(measurement.totalVoltage)} V',
          ),
          _resultLine(
            'Écart maximal tension',
            '${_formatDecimal(measurement.maximumVoltageDifference)} V',
          ),
          if (measurement.hasInternalResistance) ...[
            _resultLine(
              'Écart maximal RI',
              '${_formatDecimal(measurement.maximumInternalResistanceDifference, maxDecimals: 2)} mΩ',
            ),
          ],
          const Divider(height: 24),
          for (var index = 0; index < measurement.cellVoltages.length; index++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Cellule ${index + 1}'),
              trailing: Text(
                measurement.hasInternalResistance &&
                        index < measurement.cellInternalResistances.length
                    ? '${_formatDecimal(measurement.cellVoltages[index])} V • '
                          '${_formatDecimal(measurement.cellInternalResistances[index], maxDecimals: 2)} mΩ'
                    : '${_formatDecimal(measurement.cellVoltages[index])} V',
              ),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _addMeasurement(
                  measurement.measurementType,
                  initialMeasurement: measurement,
                  afterChargeState: measurement.isAfterCharge
                      ? _afterChargeStateFromMeasurement(measurement)
                      : null,
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modifier le relevé'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _deleteMeasurement(measurement),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer le relevé'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultLine(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          const SizedBox(width: 12),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
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
          child: Text(value, textAlign: TextAlign.end),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    final localDate = date.toLocal();
    final day = localDate.day.toString().padLeft(2, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final year = localDate.year.toString();
    final hour = localDate.hour.toString().padLeft(2, '0');
    final minute = localDate.minute.toString().padLeft(2, '0');

    return '$day/$month/$year à $hour:$minute';
  }
}

class _ResistanceThresholds {
  const _ResistanceThresholds({required this.warning, required this.critical});

  final double warning;
  final double critical;
}

class _VoltageSpreadThresholds {
  const _VoltageSpreadThresholds({
    required this.warning,
    required this.critical,
  });

  final double warning;
  final double critical;
}

enum _BatteryHealthLevel { notEvaluated, good, warning, hs }

class _MeasurementAnalysis {
  const _MeasurementAnalysis({
    required this.level,
    required this.voltageSpread,
    required this.voltageLabel,
    required this.resistanceSpread,
    required this.resistanceLabel,
    required this.resistanceEvolutionPercent,
    required this.evolutionLabel,
    required this.cellMessages,
    required this.globalMessages,
  });

  final _BatteryHealthLevel level;
  final double voltageSpread;
  final String voltageLabel;
  final double resistanceSpread;
  final String resistanceLabel;
  final double? resistanceEvolutionPercent;
  final String evolutionLabel;
  final List<String> cellMessages;
  final List<String> globalMessages;

  bool get hasWarning => level == _BatteryHealthLevel.warning;

  bool get hasCritical => level == _BatteryHealthLevel.hs;

  String get label {
    return switch (level) {
      _BatteryHealthLevel.notEvaluated => 'Non évaluée*',
      _BatteryHealthLevel.good => 'Bonne*',
      _BatteryHealthLevel.warning => 'À surveiller*',
      _BatteryHealthLevel.hs => 'HS*',
    };
  }
}
