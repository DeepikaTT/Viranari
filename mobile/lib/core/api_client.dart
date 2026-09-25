import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl})
      : baseUrl = baseUrl ??
            const String.fromEnvironment(
              'VIRANARI_API_BASE',
              defaultValue: 'http://10.0.2.2:8000',
            );

  final String baseUrl;
  String? accessToken;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  Never _throw(http.Response r) {
    var message = 'Request failed (${r.statusCode})';
    try {
      final decoded = jsonDecode(r.body) as Map<String, dynamic>;
      message = decoded['detail']?.toString() ?? decoded['message']?.toString() ?? message;
    } catch (_) {}
    throw ApiException(message, statusCode: r.statusCode);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      final r = await http
          .post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode < 200 || r.statusCode >= 300) _throw(r);
      return jsonDecode(r.body) as Map<String, dynamic>;
    } on SocketException {
      throw ApiException('No network connection');
    } on TimeoutException {
      throw ApiException('Server response timed out');
    }
  }

  Future<dynamic> _get(String path) async {
    try {
      final r = await http.get(Uri.parse('$baseUrl$path'), headers: _headers).timeout(const Duration(seconds: 8));
      if (r.statusCode < 200 || r.statusCode >= 300) _throw(r);
      return jsonDecode(r.body);
    } on SocketException {
      throw ApiException('No network connection');
    } on TimeoutException {
      throw ApiException('Server response timed out');
    }
  }

  Future<dynamic> _delete(String path) async {
    try {
      final r = await http.delete(Uri.parse('$baseUrl$path'), headers: _headers).timeout(const Duration(seconds: 8));
      if (r.statusCode < 200 || r.statusCode >= 300) _throw(r);
      return jsonDecode(r.body);
    } on SocketException {
      throw ApiException('No network connection');
    } on TimeoutException {
      throw ApiException('Server response timed out');
    }
  }

  Future<bool> health() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 3));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<({String token, UserProfile user})> register(String name, String email, String password) async {
    final data = await _post('/auth/register', {'name': name, 'email': email, 'password': password});
    return (token: data['access_token'] as String, user: UserProfile.fromJson(data['user'] as Map<String, dynamic>));
  }

  Future<({String token, UserProfile user})> login(String email, String password) async {
    final data = await _post('/auth/login', {'email': email, 'password': password});
    return (token: data['access_token'] as String, user: UserProfile.fromJson(data['user'] as Map<String, dynamic>));
  }

  Future<UserProfile> me() async => UserProfile.fromJson(await _get('/me') as Map<String, dynamic>);

  Future<List<TrustedContact>> contacts() async =>
      (await _get('/contacts') as List<dynamic>).map((e) => TrustedContact.fromJson(e as Map<String, dynamic>)).toList();

  Future<TrustedContact> inviteContact(String email, String alias) async => TrustedContact.fromJson(
        await _post('/contacts/invite', {'email': email, 'alias': alias}),
      );

  Future<TrustedContact> acceptInvite(String token) async => TrustedContact.fromJson(
        await _post('/contacts/accept', {'invite_token': token}),
      );

  Future<void> removeContact(String id) async => _delete('/contacts/$id');

  Future<AlertRecord> sendAlert(QueuedAlert alert) async => AlertRecord.fromJson(
        await _post('/alerts', alert.toJson()),
      );

  Future<AlertRecord?> findByIdempotency(String key) async {
    try {
      return AlertRecord.fromJson(await _get('/alerts/by-idempotency/$key') as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<AlertRecord?> activeAlert() async {
    try {
      return AlertRecord.fromJson(await _get('/alerts/active') as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<AlertRecord>> history() async =>
      (await _get('/alerts/history') as List<dynamic>).map((e) => AlertRecord.fromJson(e as Map<String, dynamic>)).toList();

  Future<AlertRecord> getAlert(String id) async => AlertRecord.fromJson(await _get('/alerts/detail/$id') as Map<String, dynamic>);

  Future<AlertRecord> updateLocation(
    String alertId, {
    required double latitude,
    required double longitude,
    double? accuracyM,
    int? batteryPercent,
    String? networkState,
  }) async =>
      AlertRecord.fromJson(
        await _post('/alerts/$alertId/location', {
          'latitude': latitude,
          'longitude': longitude,
          'accuracy_m': accuracyM,
          'battery_percent': batteryPercent,
          'network_state': networkState,
        }),
      );

  Future<List<AlertLocationPoint>> locations(String alertId) async =>
      (await _get('/alerts/$alertId/locations') as List<dynamic>)
          .map((e) => AlertLocationPoint.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<AlertRecord> resolveAlert(String alertId) async =>
      AlertRecord.fromJson(await _post('/alerts/$alertId/resolve', const {}));

  Future<AlertRecord> cancelAlert(String alertId) async =>
      AlertRecord.fromJson(await _post('/alerts/$alertId/cancel', const {}));

  Future<List<InboxAlert>> inbox() async =>
      (await _get('/alerts/inbox') as List<dynamic>).map((e) => InboxAlert.fromJson(e as Map<String, dynamic>)).toList();

  Future<void> acknowledge(String alertId) async => _post('/alerts/$alertId/acknowledge', const {});
}
