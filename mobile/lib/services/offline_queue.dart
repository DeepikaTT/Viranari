import '../core/api_client.dart';
import '../core/models.dart';
import '../core/storage.dart';

class OfflineQueueService {
  OfflineQueueService({QueueStore? store}) : store = store ?? QueueStore();
  final QueueStore store;

  Future<int> count() async => (await store.load()).length;
  Future<void> enqueue(QueuedAlert alert) => store.add(alert);

  Future<int> flush(ApiClient api) async {
    final items = await store.load();
    final remaining = <QueuedAlert>[];
    var resolved = 0;

    for (final alert in items) {
      try {
        // Critical timeout recovery: the original POST may have reached the
        // server even when the phone never received the response.
        final existing = await api.findByIdempotency(alert.idempotencyKey);
        if (existing != null) {
          resolved++;
          continue;
        }
        await api.sendAlert(alert);
        resolved++;
      } catch (_) {
        remaining.add(alert);
      }
    }

    await store.save(remaining);
    return resolved;
  }
}
