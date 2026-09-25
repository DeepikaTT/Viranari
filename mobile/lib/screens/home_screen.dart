import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/storage.dart';
import '../core/theme.dart';
import '../services/device_status_service.dart';
import '../services/location_service.dart';
import '../services/location_sync_service.dart';
import '../services/offline_queue.dart';
import '../services/sms_fallback_service.dart';
import '../widgets/sos_button.dart';
import 'presence_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final AppSession session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _location = LocationService();
  final _device = DeviceStatusService();
  final _queue = OfflineQueueService();
  final _phoneStore = TrustedPhoneStore();
  final _settings = SafetySettingsStore();
  final _sms = SmsFallbackService();
  final _locationSync = LocationSyncService();
  final _connectivity = Connectivity();

  bool _busy = false;
  bool _backendOnline = false;
  bool _sendingLiveUpdate = false;
  bool _testMode = false;
  bool _smsReady = false;
  bool _backgroundAlways = false;
  int _pending = 0;
  int _trustedCount = 0;
  int _trustedSmsCount = 0;
  int _queuedLocations = 0;
  int? _battery;
  String _network = 'checking';
  String _message = 'Ready. Press and hold SOS when you need help.';
  String? _syncError;
  DateTime? _lastPhoneFix;
  DateTime? _lastServerSync;
  Position? _lastPosition;
  AlertRecord? _latest;
  StreamSubscription<Position>? _liveLocationSubscription;
  Timer? _statusTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _heartbeatRunning = false;
  bool _recoveryRunning = false;
  bool _offlineSmsSentForOutage = false;
  bool _outageSmsAttemptRunning = false;
  DateTime? _lastSmsAttemptAt;
  int _consecutiveBackendFailures = 0;
  DateTime? _lastHeartbeatAt;
  DateTime? _lastForcedGpsAt;
  DateTime? _lastPresencePublishAt;
  DateTime? _lastJourneyRefreshAt;
  bool _presenceEnabled = false;
  JourneyRecord? _activeJourney;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
    _bootstrap();
    _statusTimer = Timer.periodic(const Duration(seconds: 10), (_) => _heartbeat());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverConnectivity(reason: 'App resumed'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    _connectivitySubscription?.cancel();
    _liveLocationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _smsReady = await _settings.smsFallbackEnabled() && await _sms.isReady();
    _presenceEnabled = await _settings.safetyPresenceEnabled();
    await _refreshDeviceStatus();
    await _refreshQueue();
    await _retryPending();
    await _refreshContacts();
    await _refreshJourney();
    if (_presenceEnabled) unawaited(_publishPresence(force: true));
    try {
      final active = await widget.session.api.activeAlert();
      if (!mounted) return;
      if (active != null) {
        setState(() {
          _latest = active;
          _lastHeartbeatAt = active.lastDeviceSeenAt?.toLocal();
          _lastPhoneFix = active.lastGpsFixAt?.toLocal();
          _lastServerSync = active.lastLocationSyncAt?.toLocal();
          _message = 'Emergency session restored. Live Safety tracking is active.';
        });
        await _startLiveTracking(active.id);
      }
    } catch (_) {}
  }

  Future<void> _heartbeat() async {
    if (_heartbeatRunning) return;
    _heartbeatRunning = true;
    try {
      await _refreshDeviceStatus();
      await _retryPending();
      await _publishPresence();
      await _refreshJourneyIfDue();

      final active = _latest;
      if (active != null && active.isActive) {
        if (_backendOnline) {
          _consecutiveBackendFailures = 0;
          _offlineSmsSentForOutage = false;

          // A heartbeat is independent from GPS. This is what lets a stationary
          // victim remain LIVE instead of incorrectly becoming LAST SEEN.
          try {
            final snapshot = await _device.snapshot();
            final refreshed = await widget.session.api.heartbeat(
              active.id,
              batteryPercent: snapshot.batteryPercent,
              networkState: snapshot.networkState,
              lastGpsFixAt: _lastPhoneFix,
            );
            _lastHeartbeatAt = DateTime.now();
            if (mounted) {
              setState(() {
                _latest = refreshed;
                _battery = snapshot.batteryPercent;
                _network = snapshot.networkState;
              });
            }
          } catch (_) {
            _consecutiveBackendFailures++;
          }

          await _ensureFreshGps(active.id);
          await _flushLocationQueue(active.id);
          await _refreshLatest(silent: true);
        } else {
          _consecutiveBackendFailures++;
          if (_consecutiveBackendFailures >= 2) {
            await _maybeSendOutageSms('Internet/server connection lost during an active SOS.');
          }
        }
      }
    } finally {
      _heartbeatRunning = false;
    }
  }

  Future<void> _ensureFreshGps(String alertId) async {
    final now = DateTime.now();
    final phoneAge = _lastPhoneFix == null ? const Duration(days: 1) : now.difference(_lastPhoneFix!);
    final forceAge = _lastForcedGpsAt == null ? const Duration(days: 1) : now.difference(_lastForcedGpsAt!);
    if (phoneAge < const Duration(seconds: 20) || forceAge < const Duration(seconds: 15)) return;

    _lastForcedGpsAt = now;
    try {
      final position = await _location.current();
      await _publishPosition(alertId, position);
    } catch (e) {
      if (mounted) setState(() => _syncError = 'GPS refresh delayed: ${_cleanError(e)}');
    }
  }

  Future<void> _publishPosition(String alertId, Position position) async {
    _lastPosition = position;
    _lastPhoneFix = DateTime.now();
    if (mounted) setState(() {});
    if (_sendingLiveUpdate) return;
    _sendingLiveUpdate = true;
    try {
      final snapshot = await _device.snapshot();
      final point = QueuedLocationUpdate(
        alertId: alertId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
        batteryPercent: snapshot.batteryPercent,
        networkState: snapshot.networkState,
        speedMps: _safeSpeed(position),
        headingDeg: _safeHeading(position),
        recordedLocallyAt: DateTime.now().toUtc(),
      );
      if (_backendOnline) {
        await _locationSync.sendOrQueue(widget.session.api, point);
        _lastServerSync = DateTime.now();
        if (mounted) {
          setState(() {
            _syncError = null;
            _battery = snapshot.batteryPercent;
            _network = snapshot.networkState;
          });
        }
      } else {
        await _locationSync.store.add(point);
        if (mounted) {
          setState(() {
            _syncError = 'Offline: GPS is still being collected and will replay when the server returns.';
            _battery = snapshot.batteryPercent;
            _network = snapshot.networkState;
          });
        }
        unawaited(_maybeSendOutageSms('Internet/server connection lost during an active SOS.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _syncError = 'Server sync interrupted. GPS is still being collected securely.');
      }
      unawaited(_maybeSendOutageSms('Internet/server connection lost during an active SOS.'));
    } finally {
      _sendingLiveUpdate = false;
      await _refreshQueue();
    }
  }

  bool _isOffline(List<ConnectivityResult> results) =>
      results.isEmpty || results.every((r) => r == ConnectivityResult.none);

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    if (_isOffline(results)) {
      unawaited(_maybeSendOutageSms('Internet connection lost during an active SOS.'));
      return;
    }
    unawaited(_recoverConnectivity(reason: 'Network connection restored'));
  }

  Future<void> _maybeSendOutageSms(String reason) async {
    final active = _latest;
    if (active == null || !active.isActive || active.isTest || _offlineSmsSentForOutage || _outageSmsAttemptRunning) return;
    final now = DateTime.now();
    if (_lastSmsAttemptAt != null && now.difference(_lastSmsAttemptAt!) < const Duration(seconds: 30)) return;
    _lastSmsAttemptAt = now;
    _outageSmsAttemptRunning = true;
    try {
      // Give Android a few seconds to switch from Wi-Fi to mobile data before
      // declaring a real outage. SMS is only used when the backend remains unreachable.
      await Future.delayed(const Duration(seconds: 4));
      if (await widget.session.api.health()) {
        _offlineSmsSentForOutage = false;
        return;
      }

      if (!_smsReady) {
        if (mounted) setState(() => _syncError = '$reason SMS fallback is not prepared.');
        return;
      }

      final phones = await _phoneStore.load();
      if (phones.isEmpty) {
        if (mounted) setState(() => _syncError = '$reason No accepted Trusted Circle phone numbers are cached.');
        return;
      }

      Position? position = _lastPosition;
      try {
        position ??= await _location.current();
      } catch (_) {}
      final snapshot = await _device.snapshot();
      final latitude = position?.latitude ?? active.latitude;
      final longitude = position?.longitude ?? active.longitude;
      final payload = QueuedAlert(
        idempotencyKey: 'sms-outage-${active.id}',
        latitude: latitude,
        longitude: longitude,
        accuracyM: position?.accuracy ?? active.accuracyM,
        batteryPercent: snapshot.batteryPercent ?? active.batteryPercent,
        networkState: snapshot.networkState,
        speedMps: position == null ? null : _safeSpeed(position),
        headingDeg: position == null ? null : _safeHeading(position),
        note: reason,
      );
      final result = await _sms.send(
        recipients: phones,
        message: '${_emergencySms(payload)}\n\n$reason Live internet tracking will resume automatically when connectivity returns.',
      );
      final deliveredToTransport = result.dispatchedCount > 0 || result.composerOpened;
      if (deliveredToTransport) _offlineSmsSentForOutage = true;
      if (mounted) {
        setState(() {
          _message = deliveredToTransport
              ? 'Internet tracking interrupted. ${result.message}'
              : 'SMS fallback could not send yet. ${result.message}';
          _syncError = reason;
        });
      }
    } finally {
      _outageSmsAttemptRunning = false;
    }
  }

  Future<void> _recoverConnectivity({required String reason}) async {
    if (_recoveryRunning) return;
    _recoveryRunning = true;
    try {
      final online = await widget.session.api.health();
      if (!online) return;
      _offlineSmsSentForOutage = false;
      _consecutiveBackendFailures = 0;
      if (mounted) setState(() => _backendOnline = true);

      await _retryPending();
      AlertRecord? active = _latest;
      if (active == null || !active.isActive) {
        try {
          active = await widget.session.api.activeAlert();
          if (active != null && mounted) setState(() => _latest = active);
        } catch (_) {}
      }
      if (active == null || !active.isActive) return;

      final before = await _locationSync.queuedCount();
      await _flushLocationQueue(active.id);

      // Immediately re-establish liveness, replay the trail and publish a fresh
      // fix. The responder should not wait for another stream callback.
      try {
        final snapshot = await _device.snapshot();
        final refreshed = await widget.session.api.heartbeat(
          active.id,
          batteryPercent: snapshot.batteryPercent,
          networkState: snapshot.networkState,
          lastGpsFixAt: _lastPhoneFix,
        );
        _lastHeartbeatAt = DateTime.now();
        if (mounted) setState(() => _latest = refreshed);
      } catch (_) {}
      try {
        final position = await _location.current();
        await _publishPosition(active.id, position);
      } catch (_) {}

      await _publishPresence(force: true);
      await _refreshLatest(silent: true);
      await _startLiveTracking(active.id);
      final after = await _locationSync.queuedCount();
      if (mounted) {
        setState(() {
          _syncError = after == 0 ? null : '$after GPS point${after == 1 ? '' : 's'} still waiting to sync.';
          _message = before > 0
              ? '$reason. Replayed $before queued GPS point${before == 1 ? '' : 's'} and resumed live tracking.'
              : '$reason. Live tracking resumed.';
        });
      }
    } finally {
      _recoveryRunning = false;
    }
  }

  Future<void> _refreshDeviceStatus() async {
    final snapshot = await _device.snapshot();
    final online = await widget.session.api.health();
    if (!mounted) return;
    setState(() {
      _battery = snapshot.batteryPercent;
      _network = snapshot.networkState;
      _backendOnline = online;
    });
  }

  Future<void> _refreshContacts() async {
    try {
      final contacts = await widget.session.api.contacts();
      await _phoneStore.saveFromContacts(contacts);
      final active = contacts.where((c) => c.status == 'active').toList();
      final smsCount = active.where((c) => c.phoneE164 != null).length;
      if (mounted) {
        setState(() {
          _trustedCount = active.length;
          _trustedSmsCount = smsCount;
        });
      }
    } catch (_) {
      final cached = await _phoneStore.load();
      if (mounted) setState(() => _trustedSmsCount = cached.length);
    }
  }

  Future<void> _publishPresence({bool force = false}) async {
    if (!_presenceEnabled || !_backendOnline) return;
    final now = DateTime.now();
    if (!force && _lastPresencePublishAt != null && now.difference(_lastPresencePublishAt!) < const Duration(seconds: 30)) return;
    try {
      Position? position = _lastPosition;
      position ??= await _location.current();
      await widget.session.api.updatePresence(latitude: position.latitude, longitude: position.longitude);
      _lastPresencePublishAt = now;
    } catch (_) {
      // Presence is best-effort and must never interfere with SOS.
    }
  }

  Future<void> _togglePresence(bool enabled) async {
    await _settings.setSafetyPresenceEnabled(enabled);
    if (!enabled) {
      try {
        await widget.session.api.disablePresence();
      } catch (_) {}
      if (mounted) setState(() => _presenceEnabled = false);
      return;
    }
    if (mounted) setState(() => _presenceEnabled = true);
    await _publishPresence(force: true);
  }

  Future<void> _refreshJourney() async {
    try {
      final journey = await widget.session.api.activeJourney();
      _lastJourneyRefreshAt = DateTime.now();
      if (mounted) setState(() => _activeJourney = journey);
    } catch (_) {}
  }

  Future<void> _refreshJourneyIfDue() async {
    final now = DateTime.now();
    if (_lastJourneyRefreshAt != null && now.difference(_lastJourneyRefreshAt!) < const Duration(seconds: 30)) return;
    await _refreshJourney();
  }

  Future<void> _startJourneyGuard() async {
    if (_activeJourney?.isActive == true) return;
    final controller = TextEditingController();
    var minutes = 30;
    final result = await showModalBottomSheet<({String label, int minutes})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Journey Guard', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('Tell your trusted circle when you expect to arrive. If you miss the time, they will see the journey as overdue.'),
              const SizedBox(height: 18),
              TextField(
                controller: controller,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Destination', hintText: 'Hostel, home, bus stop…'),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [15, 30, 60, 120].map((m) => ChoiceChip(
                  label: Text('$m min'),
                  selected: minutes == m,
                  onSelected: (_) => setSheetState(() => minutes = m),
                )).toList(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final text = controller.text.trim();
                  if (text.length < 2) return;
                  Navigator.pop(context, (label: text, minutes: minutes));
                },
                child: const Text('Start Journey Guard'),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    try {
      Position? position;
      try {
        position = _lastPosition ?? await _location.current();
      } catch (_) {}
      final journey = await widget.session.api.startJourney(
        destinationLabel: result.label,
        durationMinutes: result.minutes,
        startLatitude: position?.latitude,
        startLongitude: position?.longitude,
      );
      if (mounted) setState(() => _activeJourney = journey);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(e))));
    }
  }

  Future<void> _finishJourneySafe() async {
    final journey = _activeJourney;
    if (journey == null) return;
    try {
      await widget.session.api.markJourneySafe(journey.id);
      if (mounted) setState(() => _activeJourney = null);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(e))));
    }
  }

  Future<void> _cancelJourney() async {
    final journey = _activeJourney;
    if (journey == null) return;
    try {
      await widget.session.api.cancelJourney(journey.id);
      if (mounted) setState(() => _activeJourney = null);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(e))));
    }
  }

  Future<void> _refreshQueue() async {
    final count = await _queue.count();
    final locationCount = await _locationSync.queuedCount();
    if (mounted) {
      setState(() {
        _pending = count;
        _queuedLocations = locationCount;
      });
    }
  }

  Future<void> _retryPending() async {
    final resolved = await _queue.flush(widget.session.api);
    if (resolved > 0) {
      try {
        final active = await widget.session.api.activeAlert();
        if (mounted && active != null) {
          setState(() {
            _latest = active;
            _lastHeartbeatAt = active.lastDeviceSeenAt?.toLocal();
            _lastPhoneFix = active.lastGpsFixAt?.toLocal();
            _lastServerSync = active.lastLocationSyncAt?.toLocal();
            _message = '$resolved queued SOS request${resolved == 1 ? '' : 's'} reached the server.';
          });
          await _startLiveTracking(active.id);
        }
      } catch (_) {}
    }
    await _refreshQueue();
  }

  double? _safeSpeed(Position p) => p.speed.isFinite && p.speed >= 0 ? p.speed : null;
  double? _safeHeading(Position p) => p.heading.isFinite && p.heading >= 0 && p.heading < 360 ? p.heading : null;

  Future<void> _startLiveTracking(String alertId) async {
    if (_liveLocationSubscription != null) return;
    try {
      final always = await _location.hasAlwaysPermission();
      final stream = await _location.liveStream();
      if (mounted) setState(() => _backgroundAlways = always);
      late final StreamSubscription<Position> subscription;
      subscription = stream.listen(
        (position) => unawaited(_publishPosition(alertId, position)),
        onError: (Object e) async {
          if (mounted) setState(() => _syncError = 'GPS stream interrupted: ${_cleanError(e)}. Restarting…');
          await subscription.cancel();
          if (identical(_liveLocationSubscription, subscription)) _liveLocationSubscription = null;
          if (_latest?.isActive == true) {
            await Future.delayed(const Duration(seconds: 2));
            if (_latest?.isActive == true) unawaited(_startLiveTracking(alertId));
          }
        },
        onDone: () async {
          if (identical(_liveLocationSubscription, subscription)) _liveLocationSubscription = null;
          if (_latest?.isActive == true) {
            await Future.delayed(const Duration(seconds: 2));
            if (_latest?.isActive == true) unawaited(_startLiveTracking(alertId));
          }
        },
      );
      _liveLocationSubscription = subscription;
    } catch (e) {
      if (mounted) setState(() => _message = '${_cleanError(e)} The SOS itself remains active.');
      if (_latest?.isActive == true) {
        await Future.delayed(const Duration(seconds: 3));
        if (_latest?.isActive == true && _liveLocationSubscription == null) {
          unawaited(_startLiveTracking(alertId));
        }
      }
    }
  }

  Future<void> _flushLocationQueue(String alertId) async {
    try {
      final synced = await _locationSync.flush(widget.session.api, alertId);
      if (synced > 0 && mounted) {
        setState(() {
          _lastServerSync = DateTime.now();
          _syncError = null;
        });
      }
    } catch (_) {}
    await _refreshQueue();
  }

  Future<void> _stopLiveTracking() async {
    await _liveLocationSubscription?.cancel();
    _liveLocationSubscription = null;
    await _locationSync.store.clear();
  }

  String _cleanError(Object e) => e.toString().replaceFirst('Bad state: ', '');

  String _emergencySms(QueuedAlert payload) {
    final user = widget.session.user?.name ?? 'A ViraNari user';
    final localTime = DateFormat('dd MMM yyyy, h:mm:ss a').format(DateTime.now());
    final map = 'https://maps.google.com/?q=${payload.latitude},${payload.longitude}';
    return 'VIRANARI SOS\n$user may be in danger.\nLocation: ${payload.latitude.toStringAsFixed(6)}, ${payload.longitude.toStringAsFixed(6)}\n$map\nTime: $localTime\nBattery: ${payload.batteryPercent ?? 'unknown'}%\nPlease call/check on them and contact local emergency help if needed.';
  }

  Future<String> _trySmsFallback(QueuedAlert payload) async {
    if (_testMode) return 'Practice mode: SMS fallback intentionally skipped.';
    if (!_smsReady) return 'SMS fallback was not prepared in advance.';
    final phones = await _phoneStore.load();
    if (phones.isEmpty) return 'No accepted Trusted Circle phone numbers are cached.';
    final result = await _sms.send(recipients: phones, message: _emergencySms(payload));
    if (result.dispatchedCount > 0) {
      return 'SMS fallback dispatched to ${result.dispatchedCount} trusted contact${result.dispatchedCount == 1 ? '' : 's'}.';
    }
    return result.message;
  }

  Future<void> _sendSos() async {
    if (_busy || _latest?.isActive == true) return;
    await HapticFeedback.heavyImpact();
    setState(() {
      _busy = true;
      _message = 'Getting your GPS location…';
    });

    QueuedAlert? payload;
    try {
      final position = await _location.current();
      final snapshot = await _device.snapshot();
      payload = QueuedAlert(
        idempotencyKey: const Uuid().v4(),
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
        batteryPercent: snapshot.batteryPercent,
        networkState: snapshot.networkState,
        speedMps: _safeSpeed(position),
        headingDeg: _safeHeading(position),
        isTest: _testMode,
        note: _testMode ? 'ViraNari TEST DRILL — no real emergency' : 'Emergency SOS from ViraNari mobile app',
      );

      if (mounted) setState(() => _message = 'Sending SOS to your trusted circle…');
      final alert = await widget.session.api.sendAlert(payload);
      if (mounted) {
        setState(() {
          _latest = alert;
          _lastPosition = position;
          _lastPhoneFix = DateTime.now();
          _lastHeartbeatAt = alert.lastDeviceSeenAt?.toLocal() ?? DateTime.now();
          _lastServerSync = alert.lastLocationSyncAt?.toLocal() ?? DateTime.now();
          _battery = snapshot.batteryPercent;
          _network = snapshot.networkState;
          _message = alert.isTest
              ? 'Test drill active. Trusted contacts see a TEST label.'
              : alert.recipients.isEmpty
                  ? 'SOS active, but no ViraNari recipients are connected. Move toward a staffed/public place if you safely can.'
                  : 'SOS active. ${alert.recipients.length} trusted contact${alert.recipients.length == 1 ? '' : 's'} notified.';
        });
      }
      await _startLiveTracking(alert.id);
    } on ApiException catch (e) {
      if (payload != null) {
        await _queue.enqueue(payload);
        final sms = await _trySmsFallback(payload);
        if (mounted) setState(() => _message = '${e.message}. SOS queued locally. $sms');
      } else if (mounted) {
        setState(() => _message = e.message);
      }
    } catch (e) {
      if (payload != null) {
        await _queue.enqueue(payload);
        final sms = await _trySmsFallback(payload);
        if (mounted) setState(() => _message = 'Internet/server unavailable. SOS queued locally. $sms');
      } else if (mounted) {
        setState(() => _message = _cleanError(e));
      }
    } finally {
      await _refreshQueue();
      await _refreshContacts();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshLatest({bool silent = false}) async {
    if (_latest == null) return;
    try {
      final refreshed = await widget.session.api.getAlert(_latest!.id);
      if (!mounted) return;
      setState(() {
        _latest = refreshed;
        _lastHeartbeatAt = refreshed.lastDeviceSeenAt?.toLocal() ?? _lastHeartbeatAt;
        _lastServerSync = refreshed.lastLocationSyncAt?.toLocal() ?? _lastServerSync;
        if (!silent) {
          _message = refreshed.deliveryState == 'Acknowledged'
              ? '${refreshed.acknowledgedCount} trusted contact${refreshed.acknowledgedCount == 1 ? '' : 's'} acknowledged your SOS.'
              : refreshed.deliveryState == 'Delivered'
                  ? 'SOS delivered to ${refreshed.deliveredCount} trusted contact${refreshed.deliveredCount == 1 ? '' : 's'}. Waiting for acknowledgement.'
                  : _message;
        }
      });
      if (!refreshed.isActive) await _stopLiveTracking();
    } catch (_) {}
  }

  Future<void> _resolveSafe() async {
    final alert = _latest;
    if (alert == null || !alert.isActive) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End emergency session?'),
        content: const Text('Use this only when you are safe. Trusted contacts will see that the emergency ended.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep active')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("I'm safe — end")),
        ],
      ),
    );
    if (yes != true) return;
    final updated = await widget.session.api.resolveAlert(alert.id);
    await _stopLiveTracking();
    if (mounted) setState(() {
      _latest = updated;
      _message = 'Emergency ended. The session remains in history.';
    });
  }

  Future<void> _cancelFalseAlarm() async {
    final alert = _latest;
    if (alert == null || !alert.isActive) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel as false alarm?'),
        content: const Text('Only cancel if this was accidental. If you may still be unsafe, keep the SOS active.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep SOS active')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('False alarm — cancel')),
        ],
      ),
    );
    if (yes != true) return;
    final updated = await widget.session.api.cancelAlert(alert.id);
    await _stopLiveTracking();
    if (mounted) setState(() {
      _latest = updated;
      _message = 'False alarm cancelled. The record remains in history.';
    });
  }

  Future<void> _configureSms(bool enabled) async {
    if (!enabled) {
      await _settings.setSmsFallbackEnabled(false);
      if (mounted) setState(() => _smsReady = false);
      return;
    }
    final ready = await _sms.prepare();
    await _settings.setSmsFallbackEnabled(ready);
    if (mounted) {
      setState(() => _smsReady = ready);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ready ? 'SMS fallback is prepared for emergencies.' : 'SMS fallback is not ready. Check permission and that an SMS-capable SIM is active.'),
      ));
    }
  }

  Future<void> _testSmsTransport() async {
    if (!_smsReady) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prepare SMS fallback first.')));
      return;
    }
    final phones = await _phoneStore.load();
    if (phones.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No accepted Trusted Circle phone numbers are cached yet.')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send a real test SMS?'),
        content: Text('This will use your carrier SMS service and send a clearly labelled ViraNari TEST message to ${phones.length} cached trusted contact${phones.length == 1 ? '' : 's'}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send test')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      Position? position;
      try { position = _lastPosition ?? await _location.current(); } catch (_) {}
      final snapshot = await _device.snapshot();
      final message = 'VIRANARI TEST SMS — no emergency.\n'
          'SMS fallback transport check.\n'
          'Time: ${DateFormat('dd MMM yyyy, h:mm:ss a').format(DateTime.now())}'
          '${position == null ? '' : '\nLocation test: https://maps.google.com/?q=${position.latitude},${position.longitude}'}\n'
          'Battery: ${snapshot.batteryPercent ?? 'unknown'}%';
      final result = await _sms.send(recipients: phones, message: message);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(e))));
    }
  }

  Future<void> _openPresence() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SafetyPresenceScreen(session: widget.session)));
    _presenceEnabled = await _settings.safetyPresenceEnabled();
    if (mounted) setState(() {});
  }

  Future<void> _showControls() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Safety controls', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Practice mode', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Clearly labels the SOS as a drill and never sends fallback SMS.'),
                  value: _testMode,
                  onChanged: _latest?.isActive == true ? null : (v) { setState(() => _testMode = v); setSheetState(() {}); },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('SMS fallback', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_smsReady ? 'Prepared on this device' : 'Prepare SIM/SMS permission before danger'),
                  value: _smsReady,
                  onChanged: _latest?.isActive == true ? null : (v) async { await _configureSms(v); setSheetState(() {}); },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _smsReady ? _testSmsTransport : null,
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Send a real TEST SMS'),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Safety Presence', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Opt-in anonymous nearby-device signal; no names or exact public locations.'),
                  value: _presenceEnabled,
                  onChanged: (v) async { await _togglePresence(v); setSheetState(() {}); },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime? time) => time == null ? 'waiting' : DateFormat('h:mm:ss a').format(time.toLocal());

  @override
  Widget build(BuildContext context) {
    final active = _latest?.isActive == true;
    final latest = _latest;
    final lowBattery = (_battery ?? 100) <= 20;
    final online = _backendOnline;
    final journey = _activeJourney;
    final journeyOverdue = journey != null && journey.expectedArrivalAt.toLocal().isBefore(DateTime.now());

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshDeviceStatus();
        await _refreshContacts();
        await _refreshLatest();
        await _refreshJourney();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Live Safety', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: ViraColors.plum)),
                    const SizedBox(height: 3),
                    Text(active ? 'Emergency protection is active.' : 'Ready when you need it.', style: const TextStyle(color: ViraColors.mutedPlum)),
                  ],
                ),
              ),
              IconButton.filledTonal(onPressed: _showControls, icon: const Icon(Icons.tune_rounded), tooltip: 'Safety controls'),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(color: ViraColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: ViraColors.lilacStrong)),
            child: Row(
              children: [
                _StatusDot(good: online, label: online ? 'Server' : 'Offline'),
                const _SeparatorDot(),
                _StatusDot(good: _network != 'offline', label: _network.toUpperCase()),
                const _SeparatorDot(),
                _StatusDot(good: !lowBattery, label: '${_battery ?? '--'}%'),
                const Spacer(),
                Text('$_trustedCount trusted', style: const TextStyle(color: ViraColors.mutedPlum, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Center(child: SosButton(onPressed: active ? null : _sendSos, busy: _busy, label: _testMode ? 'HOLD TEST SOS' : null)),
          const SizedBox(height: 12),
          Text(
            active ? 'SOS ACTIVE · keep the phone with you if safe' : 'Press and hold · no typing required',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900, color: active ? ViraColors.pinkDark : ViraColors.plum),
          ),
          const SizedBox(height: 18),
          if (active && latest != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: ViraColors.dangerSoft, borderRadius: BorderRadius.circular(22)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_rounded, color: ViraColors.pinkDark),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Emergency session', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                      Text(latest.deliveryState, style: const TextStyle(fontWeight: FontWeight.w900, color: ViraColors.pinkDark)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('${latest.acknowledgedCount}/${latest.recipients.length} responding · ${latest.deliveredCount}/${latest.recipients.length} delivered'),
                  const SizedBox(height: 5),
                  Text(_message, style: const TextStyle(color: ViraColors.mutedPlum, height: 1.35)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: FilledButton.tonal(onPressed: _resolveSafe, child: const Text("I'm safe"))),
                      const SizedBox(width: 8),
                      TextButton(onPressed: _cancelFalseAlarm, child: const Text('False alarm')),
                    ],
                  ),
                ],
              ),
            )
          else
            Text(_message, textAlign: TextAlign.center, style: const TextStyle(color: ViraColors.mutedPlum, height: 1.35)),
          const SizedBox(height: 18),
          if (journey != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: journeyOverdue ? ViraColors.dangerSoft : ViraColors.successSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Icon(journeyOverdue ? Icons.timer_off_rounded : Icons.route_rounded, color: journeyOverdue ? ViraColors.pinkDark : ViraColors.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(journeyOverdue ? 'Journey overdue' : 'Journey Guard active', style: const TextStyle(fontWeight: FontWeight.w900)),
                        Text('${journey.destinationLabel} · expected ${DateFormat('h:mm a').format(journey.expectedArrivalAt.toLocal())}', style: const TextStyle(color: ViraColors.mutedPlum)),
                      ],
                    ),
                  ),
                  TextButton(onPressed: _finishJourneySafe, child: const Text("I'm safe")),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(child: _QuickAction(icon: Icons.route_rounded, label: journey == null ? 'Journey' : 'Journey active', onTap: journey == null ? _startJourneyGuard : _cancelJourney)),
              const SizedBox(width: 10),
              Expanded(child: _QuickAction(icon: Icons.radar_rounded, label: 'Nearby', onTap: _openPresence)),
              const SizedBox(width: 10),
              Expanded(child: _QuickAction(icon: Icons.sms_outlined, label: _smsReady ? 'SMS ready' : 'SMS setup', onTap: _showControls)),
            ],
          ),
          const SizedBox(height: 18),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: const Text('Technical status', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(active ? 'Tracking health and fallback state' : 'Tap only when you need diagnostics'),
            children: [
              _CompactMetric(label: 'Phone GPS fix', value: _fmt(_lastPhoneFix), good: _lastPhoneFix != null),
              _CompactMetric(label: 'Server location sync', value: _fmt(_lastServerSync), good: _lastServerSync != null && _syncError == null),
              _CompactMetric(label: 'Device heartbeat', value: _fmt(_lastHeartbeatAt ?? latest?.lastDeviceSeenAt), good: online),
              _CompactMetric(label: 'Queued GPS', value: '$_queuedLocations', good: _queuedLocations == 0),
              _CompactMetric(label: 'Queued SOS', value: '$_pending', good: _pending == 0),
              _CompactMetric(label: 'SMS contacts cached', value: '$_trustedSmsCount', good: _trustedSmsCount > 0),
              if (_lastPosition != null) _CompactMetric(label: 'GPS accuracy', value: '±${_lastPosition!.accuracy.toStringAsFixed(0)} m', good: _lastPosition!.accuracy < 30),
              if (_syncError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_syncError!, style: const TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w800)),
                ),
              if (active && !_backgroundAlways)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Expanded(child: Text('For strongest background tracking, allow location all the time.', style: TextStyle(color: ViraColors.warning))),
                      TextButton(onPressed: _location.openAppSettings, child: const Text('Settings')),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.good, required this.label});
  final bool good;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: good ? ViraColors.success : ViraColors.pinkDark)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      );
}

class _SeparatorDot extends StatelessWidget {
  const _SeparatorDot();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text('·', style: TextStyle(color: ViraColors.mutedPlum)),
      );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
          decoration: BoxDecoration(color: ViraColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: ViraColors.lilacStrong)),
          child: Column(
            children: [
              Icon(icon, color: ViraColors.plum),
              const SizedBox(height: 7),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ],
          ),
        ),
      );
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.label, required this.value, required this.good});
  final String label;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(good ? Icons.check_circle_rounded : Icons.schedule_rounded, size: 17, color: good ? ViraColors.success : ViraColors.warning),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

