import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

class SessionStore {
  static const _tokenKey = 'viranari_access_token';
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  Future<void> saveToken(String token) => _secure.write(key: _tokenKey, value: token);
  Future<String?> readToken() => _secure.read(key: _tokenKey);
  Future<void> clear() => _secure.delete(key: _tokenKey);
}

class QueueStore {
  static const _key = 'viranari_pending_alerts_v13';
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<List<QueuedAlert>> load() async {
    final raw = await _secure.read(key: _key);
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((item) => QueuedAlert.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<void> save(List<QueuedAlert> alerts) async {
    await _secure.write(key: _key, value: jsonEncode(alerts.map((e) => e.toJson()).toList()));
  }

  Future<void> add(QueuedAlert alert) async {
    final items = await load();
    if (items.any((e) => e.idempotencyKey == alert.idempotencyKey)) return;
    await save([...items, alert]);
  }
}

class LocationQueueStore {
  static const _key = 'viranari_location_queue_v13';
  static const maxItems = 120;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<List<QueuedLocationUpdate>> load() async {
    final raw = await _secure.read(key: _key);
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => QueuedLocationUpdate.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> save(List<QueuedLocationUpdate> items) async {
    final bounded = items.length > maxItems ? items.sublist(items.length - maxItems) : items;
    await _secure.write(key: _key, value: jsonEncode(bounded.map((e) => e.toJson()).toList()));
  }

  Future<void> add(QueuedLocationUpdate item) async {
    final items = await load();
    await save([...items, item]);
  }

  Future<void> clear() => _secure.delete(key: _key);
}
