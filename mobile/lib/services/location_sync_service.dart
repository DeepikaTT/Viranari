import 'dart:async';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/storage.dart';

class LocationSyncService {
  LocationSyncService({LocationQueueStore? store}) : store = store ?? LocationQueueStore();
  final LocationQueueStore store;

  Future<void> _queueBarrier = Future.value();
  Future<int>? _flushInFlight;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queueBarrier = _queueBarrier.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<int> queuedCount() => _serialized(() async => (await store.load()).length);

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
      await _serialized(() => store.add(point));
      rethrow;
    }
  }

  Future<int> flush(ApiClient api, String activeAlertId) {
    final current = _flushInFlight;
    if (current != null) return current;

    final future = _serialized(() => _flushLocked(api, activeAlertId));
    _flushInFlight = future;
    return future.whenComplete(() {
      if (identical(_flushInFlight, future)) _flushInFlight = null;
    });
  }

  Future<int> _flushLocked(ApiClient api, String activeAlertId) async {
    final items = await store.load();
    final target = items.where((p) => p.alertId == activeAlertId).toList();
    if (target.isEmpty) return 0;

    final untouched = items.where((p) => p.alertId != activeAlertId).toList();
    var synced = 0;
    final failed = <QueuedLocationUpdate>[];

    const batchSize = 40;
    for (var start = 0; start < target.length; start += batchSize) {
      final end = (start + batchSize < target.length) ? start + batchSize : target.length;
      final batch = target.sublist(start, end);
      try {
        final accepted = await api.updateLocationBatch(activeAlertId, batch);
        if (accepted != batch.length) {
          failed.addAll(batch.skip(accepted.clamp(0, batch.length).toInt()));
        }
        synced += accepted;
      } catch (_) {
        failed.addAll(batch);
      }
    }

    await store.save([...untouched, ...failed]);
    return synced;
  }
}
