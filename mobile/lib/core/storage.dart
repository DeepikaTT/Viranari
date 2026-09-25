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
  static const _key = 'viranari_pending_alerts_v12';
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<List<QueuedAlert>> load() async {
    final raw = await _secure.read(key: _key);
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((item) => QueuedAlert.fromJson(item as Map<String, dynamic>))
        .toList();
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
