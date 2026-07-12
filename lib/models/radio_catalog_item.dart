enum RadioLevel {
  basic,
  intermediate,
  advanced,
}

enum RadioType {
  wheel,
  sticks,
}

class RadioCatalogItem {
  const RadioCatalogItem({
    required this.id,
    required this.brand,
    required this.model,
    required this.level,
    required this.type,
    required this.channels,
    required this.protocols,
    required this.programmable,
  });

  final String id;
  final String brand;
  final String model;
  final RadioLevel level;
  final RadioType type;
  final int channels;
  final List<String> protocols;
  final bool programmable;

  String get fullName => '$brand $model';

  String get levelValue {
    switch (level) {
      case RadioLevel.basic:
        return 'basic';
      case RadioLevel.intermediate:
        return 'intermediate';
      case RadioLevel.advanced:
        return 'advanced';
    }
  }

  String get levelLabel {
    switch (level) {
      case RadioLevel.basic:
        return 'Basique';
      case RadioLevel.intermediate:
        return 'Intermédiaire';
      case RadioLevel.advanced:
        return 'Avancée';
    }
  }

  String get typeValue {
    switch (type) {
      case RadioType.wheel:
        return 'wheel';
      case RadioType.sticks:
        return 'sticks';
    }
  }

  String get typeLabel {
    switch (type) {
      case RadioType.wheel:
        return 'Volant';
      case RadioType.sticks:
        return 'Manches';
    }
  }
}