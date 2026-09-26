import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';

/// Small native bridge for Android notification-bar SOS alerts.
///
/// This intentionally avoids a heavy notification plugin. Incoming alerts are
/// discovered by ViraNari's existing inbox polling while the app process is
/// alive. A completely killed app still needs push infrastructure (FCM/APNs).
class NotificationService {
  static const MethodChannel _channel = MethodChannel(
    'com.viranari.viranari_app/notifications',
  );

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> requestPermission() async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } on MissingPluginException {
      // Platform wrapper has not been regenerated/patched yet.
    } on PlatformException {
      // Notification permission is best-effort and can be changed in settings.
    }
  }

  Future<void> showIncomingSos(InboxAlert alert) async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('showIncomingSosNotification', {
        'alertId': alert.alertId,
        'senderName': alert.senderName,
        'silentMode': alert.silentMode,
        'latitude': alert.latitude,
        'longitude': alert.longitude,
      });
    } on MissingPluginException {
      // Keep the in-app full-screen overlay working even without native bridge.
    } on PlatformException {
      // Notification bar is supplementary; Inbox/overlay remain available.
    }
  }


  Future<void> showNearbyEmergency({
    required String alertId,
    required String personName,
    required int distanceM,
    required bool forVictim,
  }) async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('showNearbyEmergencyNotification', {
        'alertId': alertId,
        'personName': personName,
        'distanceM': distanceM,
        'forVictim': forVictim,
      });
    } on MissingPluginException {
      // The in-app nearby banner still works if the native bridge is unavailable.
    } on PlatformException {
      // Proximity notification is supplementary.
    }
  }

  Future<void> cancelIncomingSos(String alertId) async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('cancelIncomingSosNotification', {
        'alertId': alertId,
      });
    } on MissingPluginException {
      // No-op.
    } on PlatformException {
      // No-op.
    }
  }
}
