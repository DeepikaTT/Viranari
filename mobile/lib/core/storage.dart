import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

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

/// Durable GPS journal for prolonged connectivity loss.
///
/// V1.5 used secure storage with a 120-point cap, which only preserved roughly
/// ten minutes at a five-second update interval. V1.6 moves location telemetry
/// into SQLite and keeps up to 100,000 points (about 5.8 days at 5 seconds).
class LocationQueueStore {
  static const _legacyKey = 'viranari_location_queue_v13';
  static const maxItems = 100000;
  static Database? _database;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<Database> _db() async {
    final current = _database;
    if (current != null) return current;
    final base = await getDatabasesPath();
    final db = await openDatabase(
      '$base/viranari_offline_journal.db',
      version: 1,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE location_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            alert_id TEXT NOT NULL,
            recorded_at TEXT NOT NULL,
            payload_json TEXT NOT NULL
          )
        ''');
        await database.execute('CREATE INDEX idx_location_queue_alert ON location_queue(alert_id, id)');
      },
    );
    _database = db;
    await _migrateLegacyIfNeeded(db);
    return db;
  }

  Future<void> _migrateLegacyIfNeeded(Database db) async {
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM location_queue')) ?? 0;
    if (count > 0) return;
    final raw = await _secure.read(key: _legacyKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final batch = db.batch();
      for (final value in list) {
        final map = value as Map<String, dynamic>;
        final point = QueuedLocationUpdate.fromJson(map);
        batch.insert('location_queue', {
          'alert_id': point.alertId,
          'recorded_at': point.recordedLocallyAt.toUtc().toIso8601String(),
          'payload_json': jsonEncode(point.toJson()),
        });
      }
      await batch.commit(noResult: true);
      await _secure.delete(key: _legacyKey);
    } catch (_) {
      // Keep the old value intact if migration fails so it can be recovered.
    }
  }

  Future<List<QueuedLocationUpdate>> load() async {
    final db = await _db();
    final rows = await db.query('location_queue', orderBy: 'id ASC');
    return rows
        .map((row) => QueuedLocationUpdate.fromJson(jsonDecode(row['payload_json'] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<QueuedLocationUpdate> items) async {
    final db = await _db();
    final bounded = items.length > maxItems ? items.sublist(items.length - maxItems) : items;
    await db.transaction((txn) async {
      await txn.delete('location_queue');
      final batch = txn.batch();
      for (final item in bounded) {
        batch.insert('location_queue', {
          'alert_id': item.alertId,
          'recorded_at': item.recordedLocallyAt.toUtc().toIso8601String(),
          'payload_json': jsonEncode(item.toJson()),
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> add(QueuedLocationUpdate item) async {
    final db = await _db();
    await db.insert('location_queue', {
      'alert_id': item.alertId,
      'recorded_at': item.recordedLocallyAt.toUtc().toIso8601String(),
      'payload_json': jsonEncode(item.toJson()),
    });
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM location_queue')) ?? 0;
    if (count > maxItems) {
      final remove = count - maxItems;
      await db.rawDelete(
        'DELETE FROM location_queue WHERE id IN (SELECT id FROM location_queue ORDER BY id ASC LIMIT ?)',
        [remove],
      );
    }
  }

  Future<void> clear() async {
    final db = await _db();
    await db.delete('location_queue');
  }
}

/// Small encrypted cache used so calls and SMS fallback still know the trusted
/// phone numbers when the backend itself is unreachable.
class TrustedContactCacheStore {
  static const _key = 'viranari_trusted_contact_cache_v16';
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<void> save(List<TrustedContact> contacts) async {
    final values = contacts
        .where((c) => c.status == 'active' && c.phoneE164 != null && c.phoneE164!.isNotEmpty)
        .map((c) => {
              'id': c.id,
              'contact_name': c.name,
              'contact_email': c.email,
              'alias': c.alias,
              'status': c.status,
              'contact_phone_e164': c.phoneE164,
            })
        .toList();
    await _secure.write(key: _key, value: jsonEncode(values));
  }

  Future<List<TrustedContact>> load() async {
    final raw = await _secure.read(key: _key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => TrustedContact.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }
}
