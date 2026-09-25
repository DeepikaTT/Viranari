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

  Future<bool> prepare() async {
    if (Platform.isAndroid) {
      final status = await Permission.sms.request();
      return status.isGranted;
    }
    if (Platform.isIOS) return true;
    return false;
  }

  Future<bool> isReady() async {
    if (Platform.isAndroid) {
      final status = await Permission.sms.status;
      return status.isGranted;
    }
    return Platform.isIOS;
  }

  Future<SmsFallbackResult> send({required List<String> recipients, required String message}) async {
    if (recipients.isEmpty) {
      return const SmsFallbackResult(dispatchedCount: 0, composerOpened: false, message: 'No trusted phone numbers cached.');
    }
    if (Platform.isAndroid) {
      final status = await Permission.sms.status;
      if (!status.isGranted) {
        return const SmsFallbackResult(dispatchedCount: 0, composerOpened: false, message: 'SMS permission was not prepared before the emergency.');
      }
      try {
        final count = await _channel.invokeMethod<int>('sendSms', {
          'recipients': recipients,
          'message': message,
        });
        return SmsFallbackResult(
          dispatchedCount: count ?? 0,
          composerOpened: false,
          message: 'SMS fallback dispatched through the phone network.',
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
