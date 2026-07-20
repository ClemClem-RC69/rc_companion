import 'package:flutter/material.dart';

import '../../../models/model_history_event.dart';
import '../../../models/rc_model.dart';

class ModelHistoryEventFormPage extends StatefulWidget {
  const ModelHistoryEventFormPage({
    super.key,
    required this.modelId,
    required this.model,
    this.existingEvent,
  });

  final String modelId;
  final RcModel model;
  final ModelHistoryEvent? existingEvent;

  bool get isEditing => existingEvent != null;

  @override
  State<ModelHistoryEventFormPage> createState() =>
      _ModelHistoryEventFormPageState();
}

class _ModelHistoryEventFormPageState extends State<ModelHistoryEventFormPage> {
  late final TextEditingController titleController;
  late final TextEditingController descriptionController;
  late final TextEditingController locationController;
  late final TextEditingController costController;
  late final TextEditingController durationController;

  late DateTime eventDate;
  String eventType = 'Entretien';

  @override
  void initState() {
    super.initState();

    final existing = widget.existingEvent;

    eventDate = existing?.eventDate ?? DateTime.now();
    eventType = existing?.eventType ?? 'Entretien';

    titleController = TextEditingController(text: existing?.title ?? '');
    descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    locationController = TextEditingController(text: existing?.location ?? '');
    costController = TextEditingController(
      text: existing?.cost == null
          ? ''
          : existing!.cost!
                .toStringAsFixed(2)
                .replaceFirst(RegExp(r'0+$'), '')
                .replaceFirst(RegExp(r'\.$'), '')
                .replaceAll('.', ','),
    );
    durationController = TextEditingController(
      text: existing?.durationMinutes?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    locationController.dispose();
    costController.dispose();
    durationController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final today = DateTime.now();
    final purchaseDate = widget.model.acquisitionDate;
    final firstDate = purchaseDate == null
        ? DateTime(1900)
        : DateTime(purchaseDate.year, purchaseDate.month, purchaseDate.day);

    final selected = await showDatePicker(
      context: context,
      initialDate: eventDate.isBefore(firstDate)
          ? firstDate
          : eventDate.isAfter(today)
          ? today
          : eventDate,
      firstDate: firstDate,
      lastDate: today,
      helpText: 'Date de l’événement',
      cancelText: 'Annuler',
      confirmText: 'Valider',
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      eventDate = DateTime(
        selected.year,
        selected.month,
        selected.day,
        eventDate.hour,
        eventDate.minute,
      );
    });
  }

  Future<void> _selectTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(eventDate),
      helpText: 'Heure de l’événement',
      cancelText: 'Annuler',
      confirmText: 'Valider',
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      eventDate = DateTime(
        eventDate.year,
        eventDate.month,
        eventDate.day,
        selected.hour,
        selected.minute,
      );
    });
  }

  void _save() {
    final title = titleController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indique un titre pour l’événement')),
      );
      return;
    }

    final now = DateTime.now();
    if (eventDate.isAfter(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La date ne peut pas être dans le futur')),
      );
      return;
    }

    final purchaseDate = widget.model.acquisitionDate;
    if (purchaseDate != null) {
      final purchaseDay = DateTime(
        purchaseDate.year,
        purchaseDate.month,
        purchaseDate.day,
      );
      final eventDay = DateTime(eventDate.year, eventDate.month, eventDate.day);

      if (eventDay.isBefore(purchaseDay)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La date ne peut pas être antérieure à la date d’achat',
            ),
          ),
        );
        return;
      }
    }

    double? cost;
    final costText = costController.text.trim();
    if (costText.isNotEmpty) {
      cost = double.tryParse(costText.replaceAll(',', '.'));
      if (cost == null || cost < 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Indique un coût valide')));
        return;
      }
    }

    int? durationMinutes;
    final durationText = durationController.text.trim();
    if (durationText.isNotEmpty) {
      durationMinutes = int.tryParse(durationText);
      if (durationMinutes == null || durationMinutes <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Indique une durée valide en minutes')),
        );
        return;
      }
    }

    final existing = widget.existingEvent;

    Navigator.pop(
      context,
      ModelHistoryEvent(
        id: existing?.id ?? '',
        modelId: widget.modelId,
        eventType: eventType,
        eventDate: eventDate,
        title: title,
        description: descriptionController.text.trim(),
        location: locationController.text.trim(),
        cost: cost,
        durationMinutes: durationMinutes,
      ),
    );
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing ? 'Modifier l’événement' : 'Ajouter un événement',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: eventType,
            decoration: const InputDecoration(
              labelText: 'Type d’événement',
              border: OutlineInputBorder(),
            ),
            items: ModelHistoryEvent.eventTypes
                .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }

              setState(() {
                eventType = value;
              });
            },
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final dateField = InkWell(
                onTap: _selectDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_formatDate(eventDate))),
                    ],
                  ),
                ),
              );

              final timeField = InkWell(
                onTap: _selectTime,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Heure',
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_formatTime(eventDate))),
                    ],
                  ),
                ),
              );

              if (constraints.maxWidth >= 520) {
                return Row(
                  children: [
                    Expanded(child: dateField),
                    const SizedBox(width: 12),
                    Expanded(child: timeField),
                  ],
                );
              }

              return Column(
                children: [dateField, const SizedBox(height: 12), timeField],
              );
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Titre',
              hintText: 'Ex. Révision des différentiels',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: locationController,
            decoration: const InputDecoration(
              labelText: 'Lieu',
              hintText: 'Facultatif',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: descriptionController,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Travaux réalisés, observations, pièces utilisées…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final durationField = TextField(
                controller: durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Durée',
                  suffixText: 'min',
                  hintText: 'Facultatif',
                  border: OutlineInputBorder(),
                ),
              );

              final costField = TextField(
                controller: costController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Coût',
                  suffixText: '€',
                  hintText: 'Facultatif',
                  border: OutlineInputBorder(),
                ),
              );

              if (constraints.maxWidth >= 520) {
                return Row(
                  children: [
                    Expanded(child: durationField),
                    const SizedBox(width: 12),
                    Expanded(child: costField),
                  ],
                );
              }

              return Column(
                children: [
                  durationField,
                  const SizedBox(height: 12),
                  costField,
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(
              widget.isEditing
                  ? 'Enregistrer les modifications'
                  : 'Ajouter à l’historique',
            ),
          ),
        ],
      ),
    );
  }
}
