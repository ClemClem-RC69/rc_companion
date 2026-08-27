enum RadioControlType { button, trim, dial, switchControl, lever, auxiliary }

class RadioControlDefinition {
  const RadioControlDefinition({
    required this.key,
    required this.label,
    required this.type,
  });

  final String key;
  final String label;
  final RadioControlType type;
}

class RadioControlLayout {
  const RadioControlLayout({
    required this.brand,
    required this.model,
    required this.controls,
  });

  final String brand;
  final String model;
  final List<RadioControlDefinition> controls;
}

const List<RadioControlLayout> radioControlCatalog = [
  // ---------------------------------------------------------------------------
  // RADIO D’ORIGINE / GÉNÉRIQUE
  // ---------------------------------------------------------------------------
  RadioControlLayout(
    brand: 'Générique',
    model: 'Radio d’origine',
    controls: [
      RadioControlDefinition(
        key: 'button_1',
        label: 'Bouton 1',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'button_2',
        label: 'Bouton 2',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'button_3',
        label: 'Bouton 3',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'button_4',
        label: 'Bouton 4',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'switch_1',
        label: 'Switch 1',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_2',
        label: 'Switch 2',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_3',
        label: 'Switch 3',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_4',
        label: 'Switch 4',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'dial_1',
        label: 'Molette 1',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'dial_2',
        label: 'Molette 2',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'trim_1',
        label: 'Trim 1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trim_2',
        label: 'Trim 2',
        type: RadioControlType.trim,
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // TRAXXAS
  // ---------------------------------------------------------------------------
  RadioControlLayout(
    brand: 'Traxxas',
    model: 'TQ 2.4 GHz',
    controls: [
      RadioControlDefinition(
        key: 'st_trim',
        label: 'ST TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'th_trim',
        label: 'TH TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'st_rate',
        label: 'ST RATE',
        type: RadioControlType.dial,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Traxxas',
    model: 'TQi',
    controls: [
      RadioControlDefinition(
        key: 'steering_trim',
        label: 'Steering Trim',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'multi_function',
        label: 'Multi-Function Knob',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'shift_switch',
        label: 'Shift Switch',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'red_rocker',
        label: 'Red Rocker Switch',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 't_lock_switch',
        label: 'T-Lock Switch (CH4/CH5)',
        type: RadioControlType.switchControl,
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // SPEKTRUM
  // ---------------------------------------------------------------------------
  RadioControlLayout(
    brand: 'Spektrum',
    model: 'SLT2',
    controls: [
      RadioControlDefinition(
        key: 'st_trim',
        label: 'ST TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'th_trim',
        label: 'TH TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'st_rate',
        label: 'ST RATE',
        type: RadioControlType.dial,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Spektrum',
    model: 'SLT3',
    controls: [
      RadioControlDefinition(
        key: 'st_trim',
        label: 'ST TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'th_trim',
        label: 'TH TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'st_rate',
        label: 'ST RATE',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'ch3',
        label: 'CH 3',
        type: RadioControlType.button,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Spektrum',
    model: 'DX3 Smart',
    controls: [
      RadioControlDefinition(
        key: 'st_trim',
        label: 'ST Trim',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'th_trim',
        label: 'TH Trim',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'st_rate',
        label: 'ST Rate',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'avc_rate',
        label: 'AVC Rate',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'ch3_button',
        label: 'Channel 3 Button',
        type: RadioControlType.button,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Spektrum',
    model: 'DX3 Smart Promoto',
    controls: [
      // Les labels ci-dessous désignent les COMMANDES PHYSIQUES de la radio.
      // Les fonctions affectées au Promoto sont saisies séparément dans
      // l'onglet « Commandes radio ».
      //
      // IMPORTANT : les key existantes sont volontairement conservées afin
      // de préserver toutes les données déjà enregistrées.
      RadioControlDefinition(
        key: 'power_button',
        label: 'POWER',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ms6x_gain',
        label: 'ST RATE',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'throttle_limit',
        label: 'TH LIMIT',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'flywheel_switch',
        label: 'CH 3 (A/B)',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'steering_reverse',
        label: 'ST REV',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'front_brake_travel',
        label: 'BRAKE RATE',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'steering_sub_trim',
        label: 'ST TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'front_brake_trim',
        label: 'TH TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'bind_button',
        label: 'BIND',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ride_mode_up',
        label: 'CH 3 (A)',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ride_mode_down',
        label: 'CH 3 (B)',
        type: RadioControlType.button,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Spektrum',
    model: 'DX5C',
    controls: [
      RadioControlDefinition(
        key: 'switch_a',
        label: 'Switch A',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_b',
        label: 'Switch B',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_c',
        label: 'Switch C',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_d',
        label: 'Switch D',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_e',
        label: 'Switch E',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'button_f',
        label: 'Button F',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'knob',
        label: 'Knob',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'roller',
        label: 'Roller Wheel',
        type: RadioControlType.dial,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Spektrum',
    model: 'DX5 Rugged',
    controls: [
      RadioControlDefinition(
        key: 'switch_a',
        label: 'Switch A',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_b',
        label: 'Switch B',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_c',
        label: 'Switch C',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_d',
        label: 'Switch D',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_e',
        label: 'Switch E',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'button_f',
        label: 'Button F',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'touch_control',
        label: 'Touch Control Panel',
        type: RadioControlType.auxiliary,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Spektrum',
    model: 'DX5 Pro',
    controls: [
      RadioControlDefinition(
        key: 'switch_a',
        label: 'Switch A',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_b',
        label: 'Switch B',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_c',
        label: 'Switch C',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_d',
        label: 'Switch D',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_e',
        label: 'Switch E',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'button_f',
        label: 'Button F',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'knob',
        label: 'Knob',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'roller',
        label: 'Roller Wheel',
        type: RadioControlType.dial,
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // FLYSKY
  // ---------------------------------------------------------------------------
  RadioControlLayout(
    brand: 'FlySky',
    model: 'GT2',
    controls: [
      RadioControlDefinition(
        key: 'st_trim',
        label: 'ST.TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'th_trim',
        label: 'TH.TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'st_dr',
        label: 'ST.D/R',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'st_rev',
        label: 'ST REV',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'th_rev',
        label: 'TH REV',
        type: RadioControlType.switchControl,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'FlySky',
    model: 'GT2B',
    controls: [
      RadioControlDefinition(
        key: 'st_trim',
        label: 'ST.TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'th_trim',
        label: 'TH.TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'st_dr',
        label: 'ST.D/R',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'ch3',
        label: 'CH3',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'st_rev',
        label: 'ST REV',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'th_rev',
        label: 'TH REV',
        type: RadioControlType.switchControl,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'FlySky',
    model: 'GT3B',
    controls: [
      RadioControlDefinition(
        key: 'trim_1',
        label: 'TRIM 1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trim_2',
        label: 'TRIM 2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trim_3',
        label: 'TRIM 3',
        type: RadioControlType.trim,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'FlySky',
    model: 'GT5',
    controls: [
      RadioControlDefinition(
        key: 'trim_1',
        label: 'TR1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trim_2',
        label: 'TR2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trim_3',
        label: 'TR3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'switch_a',
        label: 'SWA',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_b',
        label: 'SWB',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_c',
        label: 'SWC',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'vr_a',
        label: 'VRA',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'vr_b',
        label: 'VRB',
        type: RadioControlType.dial,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'FlySky',
    model: 'G7P',
    controls: [
      RadioControlDefinition(
        key: 'trim_1',
        label: 'TR1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trim_2',
        label: 'TR2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trim_3',
        label: 'TR3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'switch_a',
        label: 'SWA',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_b',
        label: 'SWB',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_c',
        label: 'SWC',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'vr_a',
        label: 'VRA',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'vr_b',
        label: 'VRB',
        type: RadioControlType.dial,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'FlySky',
    model: 'G11P',
    controls: [
      RadioControlDefinition(
        key: 'tr1',
        label: 'TR1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr2',
        label: 'TR2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr3',
        label: 'TR3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'sw1',
        label: 'SW1',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'k1',
        label: 'K1',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'k2',
        label: 'K2',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'k3',
        label: 'K3',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'k4',
        label: 'K4',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'k5',
        label: 'K5',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'vr1',
        label: 'VR1',
        type: RadioControlType.dial,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'FlySky',
    model: 'Noble NB4',
    controls: [
      RadioControlDefinition(
        key: 'tr1_fb',
        label: 'TR1-FB',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr1_lr',
        label: 'TR1-LR',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr2_fb',
        label: 'TR2-FB',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr2_lr',
        label: 'TR2-LR',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'vr1_l',
        label: 'VR1-L',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'vr1_r',
        label: 'VR1-R',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'sw1_l',
        label: 'SW1-L',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw1_r',
        label: 'SW1-R',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'tr4',
        label: 'TR4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr3',
        label: 'TR3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'sw3',
        label: 'SW3',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw2',
        label: 'SW2',
        type: RadioControlType.switchControl,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'FlySky',
    model: 'Noble NB4+',
    controls: [
      RadioControlDefinition(
        key: 'tr1_fb',
        label: 'TR1-FB',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr1_lr',
        label: 'TR1-LR',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr2_fb',
        label: 'TR2-FB',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr2_lr',
        label: 'TR2-LR',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'vr1_l',
        label: 'VR1-L',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'vr1_r',
        label: 'VR1-R',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'sw1_l',
        label: 'SW1-L',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw1_r',
        label: 'SW1-R',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'tr4',
        label: 'TR4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr3',
        label: 'TR3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'sw3',
        label: 'SW3',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw2',
        label: 'SW2',
        type: RadioControlType.switchControl,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'FlySky',
    model: 'Noble Pro',
    controls: [
      RadioControlDefinition(
        key: 'trim_1',
        label: 'TR1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trim_2',
        label: 'TR2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trim_3',
        label: 'TR3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trim_4',
        label: 'TR4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trim_5',
        label: 'TR5',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'switch_1',
        label: 'SW1',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_2',
        label: 'SW2',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_3',
        label: 'SW3',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_4',
        label: 'SW4',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'vr_1',
        label: 'VR1',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'vr_2',
        label: 'VR2',
        type: RadioControlType.dial,
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // SANWA
  // ---------------------------------------------------------------------------
  RadioControlLayout(
    brand: 'Sanwa',
    model: 'MT-S',
    controls: [
      RadioControlDefinition(
        key: 'sw_1',
        label: 'SW1',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw_2',
        label: 'SW2',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'trm_1',
        label: 'TRM1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_2',
        label: 'TRM2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_3',
        label: 'TRM3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dial',
        label: 'DIAL',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'lever',
        label: 'LEVER',
        type: RadioControlType.lever,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Sanwa',
    model: 'MT-44',
    controls: [
      RadioControlDefinition(
        key: 'sw_1',
        label: 'SW1',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw_2',
        label: 'SW2',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw_3',
        label: 'SW3',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'trm_1',
        label: 'TRM1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_2',
        label: 'TRM2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_3',
        label: 'TRM3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_4',
        label: 'TRM4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dial',
        label: 'DIAL',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'lever',
        label: 'LEVER',
        type: RadioControlType.lever,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Sanwa',
    model: 'MT-5',
    controls: [
      RadioControlDefinition(
        key: 'sw_1',
        label: 'SW1',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw_2',
        label: 'SW2',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw_3',
        label: 'SW3',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'trm_1',
        label: 'TRM1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_2',
        label: 'TRM2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_3',
        label: 'TRM3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_4',
        label: 'TRM4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dial',
        label: 'DIAL',
        type: RadioControlType.dial,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Sanwa',
    model: 'M12',
    controls: [
      RadioControlDefinition(
        key: 'sw_1',
        label: 'SW1',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw_2',
        label: 'SW2',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw_3',
        label: 'SW3',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'trm_1',
        label: 'TRM1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_2',
        label: 'TRM2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_3',
        label: 'TRM3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_4',
        label: 'TRM4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_5',
        label: 'TRM5',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dial',
        label: 'DIAL',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'lever',
        label: 'LEVER',
        type: RadioControlType.lever,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Sanwa',
    model: 'M12S',
    controls: [
      RadioControlDefinition(
        key: 'sw_1',
        label: 'SW1',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw_2',
        label: 'SW2',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw_3',
        label: 'SW3',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'trm_1',
        label: 'TRM1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_2',
        label: 'TRM2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_3',
        label: 'TRM3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_4',
        label: 'TRM4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_5',
        label: 'TRM5',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dial',
        label: 'DIAL',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'lever',
        label: 'LEVER',
        type: RadioControlType.lever,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Sanwa',
    model: 'M17',
    controls: [
      RadioControlDefinition(
        key: 'sw_1',
        label: 'SW1',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw_2',
        label: 'SW2',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw_3',
        label: 'SW3',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'trm_1',
        label: 'TRM1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_2',
        label: 'TRM2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_3',
        label: 'TRM3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_4',
        label: 'TRM4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trm_5',
        label: 'TRM5',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dial',
        label: 'DIAL',
        type: RadioControlType.dial,
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // FUTABA
  // ---------------------------------------------------------------------------
  RadioControlLayout(
    brand: 'Futaba',
    model: '3PV',
    controls: [
      RadioControlDefinition(
        key: 'dt_1',
        label: 'DT1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_2',
        label: 'DT2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_3',
        label: 'DT3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'sw_1',
        label: 'SW1',
        type: RadioControlType.switchControl,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Futaba',
    model: '4PM',
    controls: [
      RadioControlDefinition(
        key: 'dt_1',
        label: 'DT1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_2',
        label: 'DT2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_3',
        label: 'DT3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_4',
        label: 'DT4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_5',
        label: 'DT5',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dl_1',
        label: 'DL1',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'sw_1',
        label: 'SW1',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw_2',
        label: 'SW2',
        type: RadioControlType.switchControl,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Futaba',
    model: '4PM Plus',
    controls: [
      RadioControlDefinition(
        key: 'dt_1',
        label: 'DT1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_2',
        label: 'DT2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_3',
        label: 'DT3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_4',
        label: 'DT4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_5',
        label: 'DT5',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dl_1',
        label: 'DL1',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'sw_1',
        label: 'SW1',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sw_2',
        label: 'SW2',
        type: RadioControlType.switchControl,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Futaba',
    model: '7PX',
    controls: [
      RadioControlDefinition(
        key: 'dt_1',
        label: 'DT1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_2',
        label: 'DT2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_3',
        label: 'DT3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_4',
        label: 'DT4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_5',
        label: 'DT5',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_6',
        label: 'DT6',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'ps_1',
        label: 'PS1',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_2',
        label: 'PS2',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_3',
        label: 'PS3',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_4',
        label: 'PS4',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_5',
        label: 'PS5',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_6',
        label: 'PS6',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'dl_1',
        label: 'DL1',
        type: RadioControlType.dial,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Futaba',
    model: '7PXR',
    controls: [
      RadioControlDefinition(
        key: 'dt_1',
        label: 'DT1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_2',
        label: 'DT2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_3',
        label: 'DT3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_4',
        label: 'DT4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_5',
        label: 'DT5',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_6',
        label: 'DT6',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'ps_1',
        label: 'PS1',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_2',
        label: 'PS2',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_3',
        label: 'PS3',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_4',
        label: 'PS4',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_5',
        label: 'PS5',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_6',
        label: 'PS6',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'dl_1',
        label: 'DL1',
        type: RadioControlType.dial,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Futaba',
    model: '10PX',
    controls: [
      RadioControlDefinition(
        key: 'dt_1',
        label: 'DT1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_2',
        label: 'DT2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_3',
        label: 'DT3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_4',
        label: 'DT4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_5',
        label: 'DT5',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_6',
        label: 'DT6',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'ps_1',
        label: 'PS1',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_2',
        label: 'PS2',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_3',
        label: 'PS3',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_4',
        label: 'PS4',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_5',
        label: 'PS5',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'dl_1',
        label: 'DL1',
        type: RadioControlType.dial,
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // KO PROPO
  // ---------------------------------------------------------------------------
  RadioControlLayout(
    brand: 'KO Propo',
    model: 'EX-2',
    controls: [
      RadioControlDefinition(
        key: 'et_1',
        label: 'ET1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'et_2',
        label: 'ET2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'et_3',
        label: 'ET3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'et_4',
        label: 'ET4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'et_5',
        label: 'ET5',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'bt_1',
        label: 'BT1',
        type: RadioControlType.button,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'KO Propo',
    model: 'EX-RR',
    controls: [
      RadioControlDefinition(
        key: 'et_1',
        label: 'ET1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'et_2',
        label: 'ET2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'et_3',
        label: 'ET3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'et_4',
        label: 'ET4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'et_5',
        label: 'ET5',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'bt_1',
        label: 'BT1',
        type: RadioControlType.button,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'KO Propo',
    model: 'EX-NEXT',
    controls: [
      RadioControlDefinition(
        key: 'et_1',
        label: 'ET1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'et_2',
        label: 'ET2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'et_3',
        label: 'ET3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'et_4',
        label: 'ET4',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'et_5',
        label: 'ET5',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'bt_1',
        label: 'BT1',
        type: RadioControlType.button,
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // RADIOMASTER
  // ---------------------------------------------------------------------------
  RadioControlLayout(
    brand: 'RadioMaster',
    model: 'MT12 4-in-1',
    controls: [
      RadioControlDefinition(
        key: 'sa',
        label: 'SA',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sb',
        label: 'SB',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sc',
        label: 'SC',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sd',
        label: 'SD',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'se',
        label: 'SE',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sf',
        label: 'SF',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 's1',
        label: 'S1',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 's2',
        label: 'S2',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'tr_1',
        label: 'TR1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr_2',
        label: 'TR2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr_3',
        label: 'TR3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr_4',
        label: 'TR4',
        type: RadioControlType.trim,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'RadioMaster',
    model: 'MT12 ELRS',
    controls: [
      RadioControlDefinition(
        key: 'sa',
        label: 'SA',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sb',
        label: 'SB',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sc',
        label: 'SC',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sd',
        label: 'SD',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'se',
        label: 'SE',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'sf',
        label: 'SF',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 's1',
        label: 'S1',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 's2',
        label: 'S2',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'tr_1',
        label: 'TR1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr_2',
        label: 'TR2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr_3',
        label: 'TR3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'tr_4',
        label: 'TR4',
        type: RadioControlType.trim,
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // KONECT
  // ---------------------------------------------------------------------------
  RadioControlLayout(
    brand: 'Konect',
    model: 'KT2',
    controls: [
      RadioControlDefinition(
        key: 'st_trim',
        label: 'ST TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'th_trim',
        label: 'TH TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'st_dr',
        label: 'ST D/R',
        type: RadioControlType.dial,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Konect',
    model: 'KT3S',
    controls: [
      RadioControlDefinition(
        key: 'st_trim',
        label: 'ST TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'th_trim',
        label: 'TH TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'st_dr',
        label: 'ST D/R',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'ch3',
        label: 'CH3',
        type: RadioControlType.button,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Konect',
    model: 'KT3X',
    controls: [
      RadioControlDefinition(
        key: 'st_trim',
        label: 'ST TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'th_trim',
        label: 'TH TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'st_dr',
        label: 'ST D/R',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'ch3',
        label: 'CH3',
        type: RadioControlType.switchControl,
      ),
    ],
  ),

  RadioControlLayout(
    brand: 'Konect',
    model: 'X9S',
    controls: [
      RadioControlDefinition(
        key: 'dt_1',
        label: 'DT1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_2',
        label: 'DT2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dt_3',
        label: 'DT3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'dl',
        label: 'DL',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'vr',
        label: 'VR',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'ps_1',
        label: 'PS1',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_2',
        label: 'PS2',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ps_3',
        label: 'PS3',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'switch_1',
        label: 'Switch 1',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'switch_2',
        label: 'Switch 2',
        type: RadioControlType.switchControl,
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // ABSIMA
  // ---------------------------------------------------------------------------
  RadioControlLayout(
    brand: 'Absima',
    model: 'CR2S V2',
    controls: [
      RadioControlDefinition(
        key: 'st_trim',
        label: 'ST.TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'th_trim',
        label: 'TH.TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'st_dr',
        label: 'ST.D/R',
        type: RadioControlType.dial,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'Absima',
    model: 'CR3P',
    controls: [
      RadioControlDefinition(
        key: 'trim_1',
        label: 'TRIM 1',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trim_2',
        label: 'TRIM 2',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'trim_3',
        label: 'TRIM 3',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'ch3',
        label: 'CH3',
        type: RadioControlType.switchControl,
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // DUMBORC
  // ---------------------------------------------------------------------------
  RadioControlLayout(
    brand: 'DumboRC',
    model: 'X4',
    controls: [
      RadioControlDefinition(
        key: 'st_trim',
        label: 'ST TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'th_trim',
        label: 'TH TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'st_dr',
        label: 'ST D/R',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'ch3',
        label: 'CH3',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ch4',
        label: 'CH4',
        type: RadioControlType.switchControl,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'DumboRC',
    model: 'X6',
    controls: [
      RadioControlDefinition(
        key: 'st_trim',
        label: 'ST TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'th_trim',
        label: 'TH TRIM',
        type: RadioControlType.trim,
      ),
      RadioControlDefinition(
        key: 'st_dr',
        label: 'ST D/R',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'ch3',
        label: 'CH3',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ch4',
        label: 'CH4',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'ch5',
        label: 'CH5',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'ch6',
        label: 'CH6',
        type: RadioControlType.dial,
      ),
    ],
  ),
  RadioControlLayout(
    brand: 'DumboRC',
    model: 'DDF-350',
    controls: [
      RadioControlDefinition(
        key: 'ch3_button',
        label: 'CH3',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ch4_button',
        label: 'CH4',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'vr5',
        label: 'VR5',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'vr6',
        label: 'VR6',
        type: RadioControlType.dial,
      ),
      RadioControlDefinition(
        key: 'ch7_3way',
        label: 'CH7',
        type: RadioControlType.switchControl,
      ),
      RadioControlDefinition(
        key: 'ch8_button',
        label: 'CH8',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ch9_button',
        label: 'CH9',
        type: RadioControlType.button,
      ),
      RadioControlDefinition(
        key: 'ch10_button',
        label: 'CH10',
        type: RadioControlType.button,
      ),
    ],
  ),
];

RadioControlLayout? radioControlLayoutFor({
  required String brand,
  required String model,
}) {
  final normalizedBrand = brand.trim().toLowerCase();
  final normalizedModel = model.trim().toLowerCase();

  for (final layout in radioControlCatalog) {
    if (layout.brand.trim().toLowerCase() == normalizedBrand &&
        layout.model.trim().toLowerCase() == normalizedModel) {
      return layout;
    }
  }

  return null;
}
