import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../models/battery.dart';
import '../../models/rc_model.dart';
import '../../models/rc_session.dart';

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  final durationController = TextEditingController(text: '15');
  final notesController = TextEditingController();

  RcModel? selectedModel;
  Battery? battery1;
  Battery? battery2;

  @override
  void dispose() {
    durationController.dispose();
    notesController.dispose();
    super.dispose();
  }

  int cellsNumber(String value) {
    return int.tryParse(value.replaceAll('S', '')) ?? 0;
  }

  CompatibilityResult checkCompatibility() {
    final model = selectedModel;

    if (model == null) {
      return const CompatibilityResult(
        isValid: false,
        message: 'Choisis un modèle.',
      );
    }

    if (model.motorization == 'Thermique') {
      return const CompatibilityResult(
        isValid: true,
        message: 'Modèle thermique : aucune batterie nécessaire.',
      );
    }

    if (battery1 == null) {
      return const CompatibilityResult(
        isValid: false,
        message: 'Sélectionne la première batterie.',
      );
    }

    if (model.batteryCount == 2 && battery2 == null) {
      return const CompatibilityResult(
        isValid: false,
        message: 'Ce modèle nécessite deux batteries.',
      );
    }

    if (model.batteryCount == 1 && battery2 != null) {
      return const CompatibilityResult(
        isValid: false,
        message: 'Ce modèle utilise une seule batterie.',
      );
    }

    if (battery1 == battery2 && battery1 != null) {
      return const CompatibilityResult(
        isValid: false,
        message: 'Tu ne peux pas sélectionner deux fois la même batterie.',
      );
    }

    final maxCells = cellsNumber(model.maxCells);
    final firstCells = cellsNumber(battery1!.cells);

    if (firstCells > maxCells) {
      return CompatibilityResult(
        isValid: false,
        message:
            '${battery1!.id} est en ${battery1!.cells}, alors que le modèle accepte ${model.maxCells} maximum.',
      );
    }

    if (model.batteryCount == 2) {
      final second = battery2!;
      final secondCells = cellsNumber(second.cells);

      if (secondCells > maxCells) {
        return CompatibilityResult(
          isValid: false,
          message:
              '${second.id} est en ${second.cells}, alors que le modèle accepte ${model.maxCells} maximum.',
        );
      }

      if (battery1!.technology != second.technology) {
        return const CompatibilityResult(
          isValid: false,
          message: 'Les deux batteries doivent avoir la même technologie.',
        );
      }

      if (battery1!.cells != second.cells) {
        return const CompatibilityResult(
          isValid: false,
          message:
              'Les deux batteries doivent avoir le même nombre de cellules.',
        );
      }

      if (battery1!.capacity != second.capacity) {
        return const CompatibilityResult(
          isValid: false,
          message: 'Les deux batteries doivent avoir la même capacité.',
        );
      }

      if (battery1!.cRate != second.cRate) {
        return const CompatibilityResult(
          isValid: false,
          message: 'Les deux batteries doivent avoir le même taux C.',
        );
      }

      if (battery1!.brand != second.brand) {
        return const CompatibilityResult(
          isValid: true,
          hasWarning: true,
          message:
              'Compatible, mais les marques sont différentes. Deux batteries identiques sont recommandées.',
        );
      }

      if (battery1!.pairId != null &&
          second.pairId != null &&
          battery1!.pairId != second.pairId) {
        return const CompatibilityResult(
          isValid: true,
          hasWarning: true,
          message:
              'Compatible, mais les batteries ne font pas partie de la même paire enregistrée.',
        );
      }
    }

    return const CompatibilityResult(
      isValid: true,
      message: 'Configuration compatible.',
    );
  }

  void saveSession() {
    final result = checkCompatibility();
    final model = selectedModel;
    final duration = int.tryParse(durationController.text.trim());

    if (!result.isValid || model == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      return;
    }

    if (duration == null || duration <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Indique une durée valide en minutes.'),
        ),
      );
      return;
    }

    final usedBatteries = <Battery>[];

    if (battery1 != null) {
      usedBatteries.add(battery1!);
    }

    if (battery2 != null) {
      usedBatteries.add(battery2!);
    }

    sessions.add(
      RcSession(
        date: DateTime.now(),
        model: model,
        batteries: usedBatteries,
        durationMinutes: duration,
        notes: notesController.text.trim(),
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session enregistrée.'),
      ),
    );

    Navigator.pop(context);
  }

  String batteryLabel(Battery battery) {
    return '${battery.id} — ${battery.brand} — ${battery.technology} — '
        '${battery.cells} — ${battery.capacity} mAh — ${battery.cRate}C';
  }

  @override
  Widget build(BuildContext context) {
    final result = checkCompatibility();
    final isElectric = selectedModel?.motorization == 'Électrique';
    final needsTwoBatteries = selectedModel?.batteryCount == 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouvelle session'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<RcModel>(
            value: selectedModel,
            decoration: const InputDecoration(
              labelText: 'Modèle utilisé',
              border: OutlineInputBorder(),
            ),
            hint: Text(
              models.isEmpty
                  ? 'Aucun modèle enregistré'
                  : 'Choisir un modèle',
            ),
            items: models
                .map(
                  (model) => DropdownMenuItem(
                    value: model,
                    child: Text(model.name),
                  ),
                )
                .toList(),
            onChanged: models.isEmpty
                ? null
                : (value) {
                    setState(() {
                      selectedModel = value;
                      battery1 = null;
                      battery2 = null;
                    });
                  },
          ),
          if (selectedModel != null) ...[
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                leading: const Icon(Icons.directions_car),
                title: Text(selectedModel!.name),
                subtitle: Text(
                  '${selectedModel!.brand} • '
                  '${selectedModel!.batteryCount} × '
                  '${selectedModel!.maxCells} max',
                ),
              ),
            ),
          ],
          if (isElectric == true) ...[
            const SizedBox(height: 20),
            const Text(
              'Batteries utilisées',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<Battery>(
              value: battery1,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Batterie 1',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code_scanner),
              ),
              hint: Text(
                batteries.isEmpty
                    ? 'Aucune batterie enregistrée'
                    : 'Sélection provisoire',
              ),
              items: batteries
                  .map(
                    (battery) => DropdownMenuItem(
                      value: battery,
                      child: Text(
                        batteryLabel(battery),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: batteries.isEmpty
                  ? null
                  : (value) {
                      setState(() {
                        battery1 = value;
                      });
                    },
            ),
            if (needsTwoBatteries) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<Battery>(
                value: battery2,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Batterie 2',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.qr_code_scanner),
                ),
                hint: const Text('Sélection provisoire'),
                items: batteries
                    .map(
                      (battery) => DropdownMenuItem(
                        value: battery,
                        child: Text(
                          batteryLabel(battery),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: batteries.isEmpty
                    ? null
                    : (value) {
                        setState(() {
                          battery2 = value;
                        });
                      },
              ),
            ],
          ],
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: Icon(
                result.isValid
                    ? result.hasWarning
                        ? Icons.warning_amber
                        : Icons.check_circle
                    : Icons.cancel,
              ),
              title: Text(
                result.isValid
                    ? result.hasWarning
                        ? 'Avertissement'
                        : 'Compatible'
                    : 'Vérification',
              ),
              subtitle: Text(result.message),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: durationController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Durée de la session (minutes)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: notesController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Réglages, problèmes, points positifs...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: saveSession,
            icon: const Icon(Icons.save),
            label: const Text('Enregistrer la session'),
          ),
        ],
      ),
    );
  }
}

class CompatibilityResult {
  const CompatibilityResult({
    required this.isValid,
    required this.message,
    this.hasWarning = false,
  });

  final bool isValid;
  final String message;
  final bool hasWarning;
}