import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'models.dart';
import 'storage.dart';

class AppSession extends ChangeNotifier {
  AppSession({ApiClient? api, SessionStore? store})
      : api = api ?? ApiClient(),
        store = store ?? SessionStore();

  final ApiClient api;
  final SessionStore store;
  final ValueNotifier<int> silentSosRequests = ValueNotifier<int>(0);
  UserProfile? user;
  bool initialized = false;

  bool get isSignedIn => user != null;

  void requestSilentSos() {
    silentSosRequests.value = silentSosRequests.value + 1;
  }

  Future<void> initialize() async {
    final token = await store.readToken();
    if (token != null) {
      api.accessToken = token;
      try {
        user = await api.me();
      } catch (_) {
        await store.clear();
        api.accessToken = null;
      }
    }
    initialized = true;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final result = await api.login(email, password);
    api.accessToken = result.token;
    user = result.user;
    await store.saveToken(result.token);
    notifyListeners();
  }

  Future<void> register(String name, String email, String password, {String? phoneE164}) async {
    final result = await api.register(name, email, password, phoneE164: phoneE164);
    api.accessToken = result.token;
    user = result.user;
    await store.saveToken(result.token);
    notifyListeners();
  }

  Future<void> updatePhone(String phoneE164) async {
    user = await api.updatePhone(phoneE164);
    notifyListeners();
  }

  Future<void> logout() async {
    await store.clear();
    api.accessToken = null;
    user = null;
    notifyListeners();
  }
}
