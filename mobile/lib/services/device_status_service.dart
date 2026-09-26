import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class DeviceSnapshot {
  const DeviceSnapshot({required this.batteryPercent, required this.networkState});
  final int? batteryPercent;
  final String networkState;
}

class DeviceStatusService {
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();

  Future<DeviceSnapshot> snapshot() async {
    int? battery;
    try {
      battery = await _battery.batteryLevel;
    } catch (_) {}

    var network = 'unknown';
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.wifi)) {
        network = 'wifi';
      } else if (results.contains(ConnectivityResult.mobile)) {
        network = 'mobile';
      } else if (results.contains(ConnectivityResult.ethernet)) {
        network = 'ethernet';
      } else if (results.contains(ConnectivityResult.vpn)) {
        network = 'vpn';
      } else if (results.contains(ConnectivityResult.none)) {
        network = 'offline';
      } else if (results.isNotEmpty) {
        network = results.first.name;
      }
    } catch (_) {}

    return DeviceSnapshot(batteryPercent: battery, networkState: network);
  }
}
