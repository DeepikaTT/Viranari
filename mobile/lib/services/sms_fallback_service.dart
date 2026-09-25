import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:url_launcher/url_launcher.dart';

class SmsFallbackResult {
  const SmsFallbackResult({required this.dispatchedCount, required this.composerOpened, required this.message});
  final int dispatchedCount;
  final bool composerOpened;
  final String message;
}

class SmsCapability {
  const SmsCapability({
    required this.platformSupported,
    required this.permissionDeclared,
    required this.permissionGranted,
    required this.smsCapable,
    required this.simReady,
    required this.subscriptionReady,
    this.defaultSubscriptionId,
  });

  final bool platformSupported;
  final bool permissionDeclared;
  final bool permissionGranted;
  final bool smsCapable;
  final bool simReady;
  final bool subscriptionReady;
  final int? defaultSubscriptionId;

  bool get ready => Platform.isIOS ||
      (platformSupported && permissionDeclared && permissionGranted && smsCapable && simReady && subscriptionReady);

  String get issue {
    if (Platform.isIOS) return 'iOS uses the system Messages composer.';
    if (!platformSupported || !smsCapable) return 'This device does not report SMS telephony capability.';
    if (!permissionDeclared) return 'SEND_SMS is missing from the installed APK. Rebuild/reinstall ViraNari after running prepare_mobile.fish.';
    if (!permissionGranted) return 'SMS permission is not granted. Tap Prepare SMS to request it.';
    if (!simReady) return 'No SMS-capable SIM/eSIM is ready. Keep airplane mode off and confirm the SIM can send a normal text.';
    if (!subscriptionReady) return 'No default SMS SIM is selected. Choose a default SMS SIM in Android settings.';
    return 'SMS fallback is ready.';
  }
}

class SmsFallbackService {
  static const _channel = MethodChannel('viranari/sms');

  Future<SmsCapability> diagnose() async {
    if (Platform.isIOS) {
      return const SmsCapability(
        platformSupported: true,
        permissionDeclared: true,
        permissionGranted: true,
        smsCapable: true,
        simReady: true,
        subscriptionReady: true,
      );
    }
    if (!Platform.isAndroid) {
      return const SmsCapability(
        platformSupported: false,
        permissionDeclared: false,
        permissionGranted: false,
        smsCapable: false,
        simReady: false,
        subscriptionReady: false,
      );
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('smsCapability');
      return SmsCapability(
        platformSupported: true,
        permissionDeclared: result?['permission_declared'] == true,
        permissionGranted: result?['permission_granted'] == true,
        smsCapable: result?['capable'] == true,
        simReady: result?['sim_ready'] == true,
        subscriptionReady: result?['subscription_ready'] == true,
        defaultSubscriptionId: result?['default_subscription_id'] as int?,
      );
    } catch (_) {
      return const SmsCapability(
        platformSupported: false,
        permissionDeclared: false,
        permissionGranted: false,
        smsCapable: false,
        simReady: false,
        subscriptionReady: false,
      );
    }
  }

  Future<SmsCapability> prepare() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<bool>('requestSmsPermission');
      } catch (_) {
        await ph.Permission.sms.request();
      }
    }
    return diagnose();
  }

  Future<bool> isReady() async => (await diagnose()).ready;

  Future<bool> openAppSettings() => ph.openAppSettings();

  Future<void> openSmsSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openSmsSettings');
    } catch (_) {}
  }

  Future<SmsFallbackResult> send({required List<String> recipients, required String message}) async {
    if (recipients.isEmpty) {
      return const SmsFallbackResult(dispatchedCount: 0, composerOpened: false, message: 'No accepted Trusted Circle phone numbers are cached on this device.');
    }

    if (Platform.isAndroid) {
      final cap = await diagnose();
      if (!cap.ready) {
        return SmsFallbackResult(dispatchedCount: 0, composerOpened: false, message: cap.issue);
      }
      try {
        final count = await _channel.invokeMethod<int>('sendSms', {
          'recipients': recipients,
          'message': message,
        });
        final sent = count ?? 0;
        return SmsFallbackResult(
          dispatchedCount: sent,
          composerOpened: false,
          message: sent > 0
              ? 'Emergency SMS submitted to the phone network for $sent trusted contact${sent == 1 ? '' : 's'}.'
              : 'The phone did not submit any SMS messages.',
        );
      } on PlatformException catch (e) {
        return SmsFallbackResult(dispatchedCount: 0, composerOpened: false, message: e.message ?? 'SMS dispatch failed.');
      }
    }

    if (Platform.isIOS) {
      final uri = Uri(scheme: 'sms', path: recipients.first, queryParameters: {'body': message});
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return SmsFallbackResult(
        dispatchedCount: 0,
        composerOpened: opened,
        message: opened ? 'Messages opened with the emergency SMS prepared. Tap Send.' : 'Could not open Messages.',
      );
    }

    return const SmsFallbackResult(dispatchedCount: 0, composerOpened: false, message: 'SMS fallback is not supported on this platform.');
  }
}
