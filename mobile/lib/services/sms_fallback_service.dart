import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class SmsFallbackResult {
  const SmsFallbackResult({required this.dispatchedCount, required this.composerOpened, required this.message});
  final int dispatchedCount;
  final bool composerOpened;
  final String message;
}

class SmsFallbackService {
  static const _channel = MethodChannel('viranari/sms');

  Future<bool> _androidCapabilityReady() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('smsCapability');
      return result?['capable'] == true && result?['sim_ready'] == true && result?['subscription_ready'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> prepare() async {
    if (Platform.isAndroid) {
      final status = await Permission.sms.request();
      if (!status.isGranted) return false;
      return _androidCapabilityReady();
    }
    if (Platform.isIOS) return true;
    return false;
  }

  Future<bool> isReady() async {
    if (Platform.isAndroid) {
      final status = await Permission.sms.status;
      if (!status.isGranted) return false;
      return _androidCapabilityReady();
    }
    return Platform.isIOS;
  }

  Future<SmsFallbackResult> send({required List<String> recipients, required String message}) async {
    if (recipients.isEmpty) {
      return const SmsFallbackResult(dispatchedCount: 0, composerOpened: false, message: 'No accepted Trusted Circle phone numbers are cached on this device.');
    }

    if (Platform.isAndroid) {
      final status = await Permission.sms.status;
      if (!status.isGranted) {
        return const SmsFallbackResult(dispatchedCount: 0, composerOpened: false, message: 'SEND_SMS permission is not granted. Enable SMS fallback before an emergency.');
      }
      if (!await _androidCapabilityReady()) {
        return const SmsFallbackResult(dispatchedCount: 0, composerOpened: false, message: 'SMS is not ready. Keep airplane mode off, confirm a SIM/eSIM can text, and select a default SMS SIM in Android settings.');
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
