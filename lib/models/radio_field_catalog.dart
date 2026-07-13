import 'package:flutter/material.dart';

class RadioFieldDefinition {
  const RadioFieldDefinition({
    required this.key,
    required this.label,
    required this.hint,
    this.multiline = false,
  });

  final String key;
  final String label;
  final String hint;
  final bool multiline;
}

class RadioFieldSection {
  const RadioFieldSection({
    required this.title,
    required this.icon,
    required this.fields,
  });

  final String title;
  final IconData icon;
  final List<RadioFieldDefinition> fields;
}

const List<RadioFieldSection> radioFieldCatalog = [
  RadioFieldSection(
    title: 'Direction',
    icon: Icons.swap_horiz,
    fields: [
      RadioFieldDefinition(
        key: 'steering_trim',
        label: 'Trim direction',
        hint: 'Exemple : +2',
      ),
      RadioFieldDefinition(
        key: 'steering_subtrim',
        label: 'Sub-trim direction',
        hint: 'Exemple : -3',
      ),
      RadioFieldDefinition(
        key: 'steering_dual_rate',
        label: 'Dual Rate direction',
        hint: 'Exemple : 90 %',
      ),
      RadioFieldDefinition(
        key: 'steering_expo',
        label: 'Expo direction',
        hint: 'Exemple : -20 %',
      ),
      RadioFieldDefinition(
        key: 'steering_speed',
        label: 'Vitesse direction',
        hint: 'Exemple : 80 %',
      ),
      RadioFieldDefinition(
        key: 'steering_left_epa',
        label: 'EPA direction gauche',
        hint: 'Exemple : 95 %',
      ),
      RadioFieldDefinition(
        key: 'steering_right_epa',
        label: 'EPA direction droite',
        hint: 'Exemple : 92 %',
      ),
      RadioFieldDefinition(
        key: 'steering_reverse',
        label: 'Inversion direction',
        hint: 'Normal ou inversé',
      ),
    ],
  ),
  RadioFieldSection(
    title: 'Gaz et frein',
    icon: Icons.speed,
    fields: [
      RadioFieldDefinition(
        key: 'throttle_trim',
        label: 'Trim gaz',
        hint: 'Exemple : 0',
      ),
      RadioFieldDefinition(
        key: 'throttle_subtrim',
        label: 'Sub-trim gaz',
        hint: 'Exemple : +1',
      ),
      RadioFieldDefinition(
        key: 'throttle_expo',
        label: 'Expo gaz',
        hint: 'Exemple : -10 %',
      ),
      RadioFieldDefinition(
        key: 'throttle_limit',
        label: 'Limite gaz',
        hint: 'Exemple : 75 %',
      ),
      RadioFieldDefinition(
        key: 'throttle_epa',
        label: 'EPA gaz',
        hint: 'Exemple : 100 %',
      ),
      RadioFieldDefinition(
        key: 'brake_epa',
        label: 'EPA frein',
        hint: 'Exemple : 80 %',
      ),
      RadioFieldDefinition(
        key: 'brake_rate',
        label: 'Puissance de frein',
        hint: 'Exemple : 70 %',
      ),
      RadioFieldDefinition(
        key: 'throttle_reverse',
        label: 'Inversion gaz',
        hint: 'Normal ou inversé',
      ),
      RadioFieldDefinition(
        key: 'abs',
        label: 'ABS',
        hint: 'Exemple : Off ou 20 %',
      ),
    ],
  ),
  RadioFieldSection(
    title: 'Gyro et assistances',
    icon: Icons.assistant_outlined,
    fields: [
      RadioFieldDefinition(
        key: 'gyro_gain',
        label: 'Gain gyro',
        hint: 'Exemple : 30 %',
      ),
      RadioFieldDefinition(
        key: 'tsm_avc',
        label: 'TSM / AVC',
        hint: 'Exemple : Off ou 25 %',
      ),
      RadioFieldDefinition(
        key: 'traction_control',
        label: 'Contrôle de traction',
        hint: 'Exemple : Off',
      ),
    ],
  ),
  RadioFieldSection(
    title: 'Voies auxiliaires',
    icon: Icons.tune,
    fields: [
      RadioFieldDefinition(
        key: 'channel_3',
        label: 'Voie 3',
        hint: 'Exemple : éclairage',
      ),
      RadioFieldDefinition(
        key: 'channel_4',
        label: 'Voie 4',
        hint: 'Exemple : treuil',
      ),
      RadioFieldDefinition(
        key: 'channel_5',
        label: 'Voie 5',
        hint: 'Fonction affectée',
      ),
      RadioFieldDefinition(
        key: 'channel_6',
        label: 'Voie 6',
        hint: 'Fonction affectée',
      ),
    ],
  ),
  RadioFieldSection(
    title: 'Boutons, molettes et interrupteurs',
    icon: Icons.gamepad_outlined,
    fields: [
      RadioFieldDefinition(
        key: 'button_1_assignment',
        label: 'Bouton 1',
        hint: 'Exemple : ABS On/Off',
      ),
      RadioFieldDefinition(
        key: 'button_2_assignment',
        label: 'Bouton 2',
        hint: 'Exemple : chronomètre',
      ),
      RadioFieldDefinition(
        key: 'button_3_assignment',
        label: 'Bouton 3',
        hint: 'Fonction affectée',
      ),
      RadioFieldDefinition(
        key: 'button_4_assignment',
        label: 'Bouton 4',
        hint: 'Fonction affectée',
      ),
      RadioFieldDefinition(
        key: 'dial_1_assignment',
        label: 'Molette 1',
        hint: 'Exemple : Dual Rate direction',
      ),
      RadioFieldDefinition(
        key: 'dial_2_assignment',
        label: 'Molette 2',
        hint: 'Exemple : puissance de frein',
      ),
      RadioFieldDefinition(
        key: 'dial_3_assignment',
        label: 'Molette 3',
        hint: 'Fonction affectée',
      ),
      RadioFieldDefinition(
        key: 'switch_1_assignment',
        label: 'Interrupteur 1',
        hint: 'Exemple : gyro On/Off',
      ),
      RadioFieldDefinition(
        key: 'switch_2_assignment',
        label: 'Interrupteur 2',
        hint: 'Fonction affectée',
      ),
      RadioFieldDefinition(
        key: 'switch_3_assignment',
        label: 'Interrupteur 3',
        hint: 'Fonction affectée',
      ),
      RadioFieldDefinition(
        key: 'trigger_1_assignment',
        label: 'Commande auxiliaire 1',
        hint: 'Fonction affectée',
      ),
      RadioFieldDefinition(
        key: 'trigger_2_assignment',
        label: 'Commande auxiliaire 2',
        hint: 'Fonction affectée',
      ),
    ],
  ),
  RadioFieldSection(
    title: 'Mixages',
    icon: Icons.merge_type,
    fields: [
      RadioFieldDefinition(
        key: 'mix_1',
        label: 'Mixage 1',
        hint: 'Fonction et valeur',
      ),
      RadioFieldDefinition(
        key: 'mix_2',
        label: 'Mixage 2',
        hint: 'Fonction et valeur',
      ),
    ],
  ),
  RadioFieldSection(
    title: 'Divers',
    icon: Icons.more_horiz,
    fields: [
      RadioFieldDefinition(
        key: 'timer',
        label: 'Timer',
        hint: 'Exemple : 8 min',
      ),
      RadioFieldDefinition(
        key: 'voltage_alarm',
        label: 'Alarme tension',
        hint: 'Exemple : 7,0 V',
      ),
      RadioFieldDefinition(
        key: 'model_memory',
        label: 'Mémoire modèle',
        hint: 'Exemple : Mémoire 3',
      ),
      RadioFieldDefinition(
        key: 'notes',
        label: 'Notes',
        hint: 'Comportement du modèle, remarques...',
        multiline: true,
      ),
    ],
  ),
];

List<RadioFieldDefinition> get allRadioFields {
  return radioFieldCatalog
      .expand((section) => section.fields)
      .toList();
}

RadioFieldDefinition? radioFieldByKey(String key) {
  for (final field in allRadioFields) {
    if (field.key == key) {
      return field;
    }
  }

  return null;
}

String radioFieldLabel(String key) {
  return radioFieldByKey(key)?.label ?? key;
}
