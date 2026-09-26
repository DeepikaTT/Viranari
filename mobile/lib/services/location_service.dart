import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<LocationPermission> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Location services are turned off. Enable GPS and try again.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw StateError('Location permission is required to attach your position to SOS.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError('Location permission is blocked. Enable it from app settings.');
    }
    return permission;
  }

  Future<bool> hasAlwaysPermission() async {
    final permission = await ensurePermission();
    return permission == LocationPermission.always || defaultTargetPlatform != TargetPlatform.android;
  }

  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Best-effort fused GPS fix.
  ///
  /// A fresh bestForNavigation fix is preferred. If Android temporarily cannot
  /// produce one before the deadline (common after screen wake / network handoff),
  /// we reuse a recent last-known fix or the caller's previous good fix rather
  /// than turning a transient GPS delay into a visible "responder timeout".
  Future<Position> currentBestEffort({Position? fallback}) async {
    await ensurePermission();
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 9),
        ),
      );
    } on TimeoutException {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        if (!age.isNegative && age <= const Duration(minutes: 2)) {
          return lastKnown;
        }
      }
      if (fallback != null) return fallback;
      rethrow;
    }
  }

  Future<Position> current() => currentBestEffort();

  Future<Stream<Position>> liveStream() async {
    await ensurePermission();
    LocationSettings settings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'ViraNari SOS ACTIVE',
          notificationText: 'Live GPS is being shared with your Trusted Circle.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.otherNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  /// Continuous responder GPS is more reliable than repeatedly asking for a
  /// one-shot fix every poll cycle. The stream also keeps producing positions
  /// through short GPS warm-up delays and network handoffs.
  Future<Stream<Position>> responderStream() async {
    await ensurePermission();
    LocationSettings settings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 4),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'ViraNari responder active',
          notificationText: 'Sharing your live location with the SOS victim.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.otherNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}
