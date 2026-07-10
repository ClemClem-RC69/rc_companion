import 'battery.dart';
import 'rc_model.dart';

class RcSession {
  RcSession({
    required this.date,
    required this.model,
    required this.batteries,
    required this.durationMinutes,
    required this.notes,
  });

  final DateTime date;
  final RcModel model;
  final List<Battery> batteries;
  final int durationMinutes;
  final String notes;
}