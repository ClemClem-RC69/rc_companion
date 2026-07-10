import '../models/battery.dart';
import '../models/rc_model.dart';
import '../models/rc_session.dart';

final List<Battery> batteries = [];
final List<RcModel> models = [];
final List<RcSession> sessions = [];

int batteryCounter = 1;
int pairCounter = 1;

String nextBatteryId(String technology) {
  final prefix = technology
      .toUpperCase()
      .replaceAll('-', '')
      .replaceAll(' ', '');

  final number = batteryCounter.toString().padLeft(3, '0');
  batteryCounter++;

  return '$prefix-$number';
}

String nextPairId() {
  final number = pairCounter.toString().padLeft(3, '0');
  pairCounter++;

  return 'P$number';
}