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
