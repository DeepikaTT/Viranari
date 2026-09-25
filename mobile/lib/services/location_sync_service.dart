import '../core/api_client.dart';
import '../core/models.dart';
import '../core/storage.dart';

class LocationSyncService {
  LocationSyncService({LocationQueueStore? store}) : store = store ?? LocationQueueStore();
  final LocationQueueStore store;

  Future<int> queuedCount() async => (await store.load()).length;

  Future<void> sendOrQueue(ApiClient api, QueuedLocationUpdate point) async {
    try {
      await api.updateLocation(
        point.alertId,
        latitude: point.latitude,
        longitude: point.longitude,
        accuracyM: point.accuracyM,
        batteryPercent: point.batteryPercent,
        networkState: point.networkState,
        speedMps: point.speedMps,
        headingDeg: point.headingDeg,
      );
    } catch (_) {
      await store.add(point);
      rethrow;
    }
  }

  Future<int> flush(ApiClient api, String activeAlertId) async {
    final items = await store.load();
    final remaining = <QueuedLocationUpdate>[];
    var synced = 0;
    for (final point in items) {
      if (point.alertId != activeAlertId) continue;
      try {
        await api.updateLocation(
          point.alertId,
          latitude: point.latitude,
          longitude: point.longitude,
          accuracyM: point.accuracyM,
          batteryPercent: point.batteryPercent,
          networkState: point.networkState,
          speedMps: point.speedMps,
          headingDeg: point.headingDeg,
        );
        synced++;
      } catch (_) {
        remaining.add(point);
      }
    }
    await store.save(remaining);
    return synced;
  }
}
