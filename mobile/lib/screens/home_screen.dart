import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../services/device_status_service.dart';
import '../services/location_service.dart';
import '../services/location_sync_service.dart';
import '../services/offline_queue.dart';
import '../widgets/sos_button.dart';
import '../widgets/status_chip.dart';
import 'safety_compass_screen.dart';
import 'safety_map_screen.dart';

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
  final _locationSync = LocationSyncService();
  final _connectivity = Connectivity();
  final MapController _emergencyMapController = MapController();

  bool _busy = false;
  bool _backendOnline = false;
  bool _sendingLiveUpdate = false;
  bool _testMode = false;
  bool _backgroundAlways = false;
  bool _heartbeatRunning = false;
  bool _recoveryRunning = false;
  bool _silentRevealed = false;
  bool _silentArming = false;
  int _lastSilentRequest = 0;

  int _pending = 0;
  int _trustedCount = 0;
  int _queuedLocations = 0;
  int? _battery;

  String _network = 'checking';
  String _message = 'Ready. Press and hold SOS when you need help.';
  String? _syncError;

  DateTime? _lastHeartbeatAt;
  DateTime? _lastPhoneFix;
  DateTime? _lastServerSync;
  DateTime? _lastForcedGpsAt;
  Position? _lastPosition;
  AlertRecord? _latest;
  List<ResponderState> _responders = const [];
  List<AlertLocationPoint> _homeVictimTrail = const [];
  List<ResponderTrailPoint> _homeResponderTrail = const [];

  StreamSubscription<Position>? _liveLocationSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastSilentRequest = widget.session.silentSosRequests.value;
    widget.session.silentSosRequests.addListener(_handleSilentSosRequest);
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
    _bootstrap();
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) => _heartbeat());
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
    widget.session.silentSosRequests.removeListener(_handleSilentSosRequest);
    _statusTimer?.cancel();
    _connectivitySubscription?.cancel();
    _liveLocationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _refreshDeviceStatus();
    await _refreshQueue();
    if (_backendOnline) await _retryPending();
    await _refreshContacts();

    try {
      final active = await widget.session.api.activeAlert();
      if (!mounted) return;
      if (active != null) {
        setState(() {
          _latest = active;
          _lastHeartbeatAt = active.lastDeviceSeenAt?.toLocal();
          _lastPhoneFix = active.lastGpsFixAt?.toLocal();
          _lastServerSync = active.lastLocationSyncAt?.toLocal();
          _silentRevealed = false;
          _message = active.silentMode ? 'Safety session restored.' : 'Emergency session restored. Live tracking resumed.';
        });
        await _refreshLatest(silent: true);
        await _startLiveTracking(active.id);
      }
    } catch (_) {
      // The local UI remains usable even if the backend is temporarily offline.
    }
  }

  void _handleSilentSosRequest() {
    final request = widget.session.silentSosRequests.value;
    if (request == _lastSilentRequest) return;
    _lastSilentRequest = request;
    if (_latest?.isActive == true) {
      if (_latest?.silentMode == true && !_silentRevealed && mounted) {
        setState(() => _silentRevealed = true);
      }
      unawaited(HapticFeedback.selectionClick());
      return;
    }
    unawaited(_sendSos(silent: true));
  }

  Future<void> _heartbeat() async {
    if (_heartbeatRunning) return;
    _heartbeatRunning = true;
    try {
      await _refreshDeviceStatus();
      if (_backendOnline) await _retryPending();

      final active = _latest;
      if (active == null || !active.isActive) return;

      if (!_backendOnline) {
        if (mounted) {
          setState(() => _syncError = 'Offline: GPS continues locally. Updates will replay when the server returns.');
        }
        return;
      }

      try {
        final snapshot = await _device.snapshot();
        final refreshed = await widget.session.api.heartbeat(
          active.id,
          batteryPercent: snapshot.batteryPercent,
          networkState: snapshot.networkState,
          lastGpsFixAt: _lastPhoneFix,
        );
        if (!mounted) return;
        setState(() {
          _latest = refreshed;
          _lastHeartbeatAt = refreshed.lastDeviceSeenAt?.toLocal() ?? DateTime.now();
          _battery = snapshot.batteryPercent;
          _network = snapshot.networkState;
        });
      } catch (_) {
        if (mounted) setState(() => _backendOnline = false);
        return;
      }

      await _ensureFreshGps(active.id);
      await _flushLocationQueue(active.id);
      await _refreshLatest(silent: true);
    } finally {
      _heartbeatRunning = false;
    }
  }

  Future<void> _ensureFreshGps(String alertId) async {
    final now = DateTime.now();
    final phoneAge = _lastPhoneFix == null ? const Duration(days: 1) : now.difference(_lastPhoneFix!);
    final forceAge = _lastForcedGpsAt == null ? const Duration(days: 1) : now.difference(_lastForcedGpsAt!);
    if (phoneAge < const Duration(seconds: 8) || forceAge < const Duration(seconds: 7)) return;

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
    if (mounted) {
      setState(() {});
      if (_latest?.isActive == true) _fitEmergencyMap();
    }
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
        try {
          await _locationSync.sendOrQueue(widget.session.api, point);
          if (mounted) {
            setState(() {
              _lastServerSync = DateTime.now();
              _syncError = null;
              _battery = snapshot.batteryPercent;
              _network = snapshot.networkState;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              _backendOnline = false;
              _syncError = 'Server sync interrupted. GPS is still being stored securely on this phone.';
            });
          }
        }
      } else {
        await _locationSync.store.add(point);
        if (mounted) {
          setState(() {
            _syncError = 'Offline: GPS is still being collected and will replay when connectivity returns.';
            _battery = snapshot.batteryPercent;
            _network = snapshot.networkState;
          });
        }
      }
    } finally {
      _sendingLiveUpdate = false;
      await _refreshQueue();
    }
  }

  bool _isOffline(List<ConnectivityResult> results) =>
      results.isEmpty || results.every((r) => r == ConnectivityResult.none);

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    if (_isOffline(results)) {
      if (mounted) {
        setState(() {
          _backendOnline = false;
          if (_latest?.isActive == true) {
            _syncError = 'Connection lost. GPS continues locally until the server is reachable again.';
          }
        });
      }
      return;
    }
    unawaited(_recoverConnectivity(reason: 'Network connection restored'));
  }

  Future<void> _recoverConnectivity({required String reason}) async {
    if (_recoveryRunning) return;
    _recoveryRunning = true;
    try {
      final online = await widget.session.api.health();
      if (!online) return;
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

      try {
        final snapshot = await _device.snapshot();
        final refreshed = await widget.session.api.heartbeat(
          active.id,
          batteryPercent: snapshot.batteryPercent,
          networkState: snapshot.networkState,
          lastGpsFixAt: _lastPhoneFix,
        );
        if (mounted) {
          setState(() {
            _latest = refreshed;
            _lastHeartbeatAt = refreshed.lastDeviceSeenAt?.toLocal() ?? DateTime.now();
          });
        }
      } catch (_) {}

      try {
        final position = await _location.current();
        await _publishPosition(active.id, position);
      } catch (_) {}

      await _refreshLatest(silent: true);
      await _startLiveTracking(active.id);
      final after = await _locationSync.queuedCount();

      if (mounted) {
        setState(() {
          _syncError = after == 0 ? null : '$after location point${after == 1 ? '' : 's'} still waiting to sync.';
          _message = before > 0
              ? '$reason. Replayed $before queued location point${before == 1 ? '' : 's'} and resumed live tracking.'
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
      final active = contacts.where((c) => c.status == 'active').length;
      if (mounted) setState(() => _trustedCount = active);
    } catch (_) {}
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
    if (!_backendOnline) return;
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
    if (!_backendOnline) return;
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


  Future<void> _openCurrentMap() async {
    final position = _lastPosition;
    final latest = _latest;
    final latitude = position?.latitude ?? latest?.latitude;
    final longitude = position?.longitude ?? latest?.longitude;
    if (latitude == null || longitude == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No GPS location is available yet.')),
        );
      }
      return;
    }
    final uri = Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude(ViraNari%20location)');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No map app could open this location.')),
      );
    }
  }

  Future<void> _openSafetyMap() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SafetyMapScreen(session: widget.session)),
    );
  }

  Future<void> _openSafetyCompass() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SafetyCompassScreen(session: widget.session)),
    );
  }

  Future<void> _revealSilentSession() async {
    await HapticFeedback.selectionClick();
    if (mounted) setState(() => _silentRevealed = true);
  }

  Future<void> _sendSos({bool silent = false}) async {
    if (_busy || _latest?.isActive == true) return;
    if (!silent) await HapticFeedback.heavyImpact();
    setState(() {
      _busy = true;
      _silentArming = silent;
      _message = silent ? 'Preparing safety session…' : 'Getting your GPS location…';
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
        silentMode: silent,
        note: _testMode
            ? 'ViraNari TEST DRILL — no real emergency'
            : silent
                ? 'Silent Safety Session from ViraNari mobile app'
                : 'Emergency SOS from ViraNari mobile app',
      );

      if (mounted) setState(() => _message = silent ? 'Starting safety session…' : 'Sending SOS to your trusted circle…');
      final alert = await widget.session.api.sendAlert(payload);
      if (mounted) {
        setState(() {
          _latest = alert;
          _lastPosition = position;
          _homeVictimTrail = [
            AlertLocationPoint(
              latitude: position.latitude,
              longitude: position.longitude,
              recordedAt: DateTime.now(),
              accuracyM: position.accuracy,
              batteryPercent: snapshot.batteryPercent,
              networkState: snapshot.networkState,
              speedMps: _safeSpeed(position),
              headingDeg: _safeHeading(position),
            ),
          ];
          _homeResponderTrail = const [];
          _lastPhoneFix = DateTime.now();
          _lastHeartbeatAt = alert.lastDeviceSeenAt?.toLocal() ?? DateTime.now();
          _lastServerSync = alert.lastLocationSyncAt?.toLocal() ?? DateTime.now();
          _battery = snapshot.batteryPercent;
          _network = snapshot.networkState;
          _backendOnline = true;
          _silentRevealed = false;
          _message = alert.silentMode
              ? 'Safety session active.'
              : alert.isTest
                  ? 'Test drill active. Trusted contacts see a TEST label.'
                  : alert.recipients.isEmpty
                      ? 'SOS active, but no Trusted Circle recipient is connected yet.'
                      : 'SOS active. ${alert.recipients.length} trusted contact${alert.recipients.length == 1 ? '' : 's'} notified.';
        });
      }
      await _startLiveTracking(alert.id);
    } on ApiException catch (e) {
      if (payload != null) {
        await _queue.enqueue(payload);
        if (mounted) setState(() => _message = '${e.message}. SOS saved securely and will retry automatically when the server returns.');
      } else if (mounted) {
        setState(() => _message = e.message);
      }
    } catch (e) {
      if (payload != null) {
        await _queue.enqueue(payload);
        if (mounted) setState(() => _message = 'Server unavailable. SOS saved securely and will retry automatically when connectivity returns.');
      } else if (mounted) {
        setState(() => _message = _cleanError(e));
      }
    } finally {
      await _refreshQueue();
      await _refreshContacts();
      if (mounted) setState(() { _busy = false; _silentArming = false; });
    }
  }

  Future<void> _refreshLatest({bool silent = false}) async {
    if (_latest == null || !_backendOnline) return;
    try {
      final alertId = _latest!.id;
      final results = await Future.wait([
        widget.session.api.getAlert(alertId),
        widget.session.api.responders(alertId),
        widget.session.api.locations(alertId),
        widget.session.api.responderTrail(alertId),
      ]);
      final refreshed = results[0] as AlertRecord;
      final responders = results[1] as List<ResponderState>;
      final victimTrail = results[2] as List<AlertLocationPoint>;
      final responderTrail = results[3] as List<ResponderTrailPoint>;
      if (!mounted) return;
      setState(() {
        _latest = refreshed;
        _responders = responders;
        _homeVictimTrail = victimTrail;
        _homeResponderTrail = responderTrail;
        _lastHeartbeatAt = refreshed.lastDeviceSeenAt?.toLocal() ?? _lastHeartbeatAt;
        _lastPhoneFix = refreshed.lastGpsFixAt?.toLocal() ?? _lastPhoneFix;
        _lastServerSync = refreshed.lastLocationSyncAt?.toLocal() ?? _lastServerSync;
        if (!silent) {
          _message = refreshed.deliveryState == 'Acknowledged'
              ? '${refreshed.acknowledgedCount} trusted contact${refreshed.acknowledgedCount == 1 ? '' : 's'} acknowledged your SOS.'
              : refreshed.deliveryState == 'Delivered'
                  ? 'SOS delivered to ${refreshed.deliveredCount} trusted contact${refreshed.deliveredCount == 1 ? '' : 's'}. Waiting for acknowledgement.'
                  : _message;
        }
      });
      if (refreshed.isActive) _fitEmergencyMap();
      if (!refreshed.isActive) await _stopLiveTracking();
    } catch (_) {}
  }

  String _responderDistance(int metres) => metres >= 1000
      ? '${(metres / 1000).toStringAsFixed(2)} km'
      : '$metres m';

  String _responderEta(int seconds) {
    if (seconds < 60) return '<1 min';
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '~$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '~${hours}h' : '~${hours}h ${rest}m';
  }

  ResponderState? get _primaryResponder {
    if (_responders.isEmpty) return null;
    final sorted = [..._responders]..sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return sorted.first;
  }

  LatLng _victimMapPoint(AlertRecord latest) {
    final local = _lastPosition;
    if (local != null) return LatLng(local.latitude, local.longitude);
    if (_homeVictimTrail.isNotEmpty) {
      final last = _homeVictimTrail.last;
      return LatLng(last.latitude, last.longitude);
    }
    return LatLng(latest.latitude, latest.longitude);
  }

  double _emergencyZoom(double distanceM) {
    if (distanceM > 30000) return 9.8;
    if (distanceM > 18000) return 10.5;
    if (distanceM > 10000) return 11.2;
    if (distanceM > 6000) return 12.0;
    if (distanceM > 3000) return 12.8;
    if (distanceM > 1500) return 13.7;
    if (distanceM > 700) return 14.6;
    return 15.6;
  }

  void _fitEmergencyMap() {
    final latest = _latest;
    if (latest == null || !latest.isActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final victim = _victimMapPoint(latest);
        final responder = _primaryResponder;
        if (responder == null) {
          _emergencyMapController.move(victim, 15.8);
          return;
        }
        final responderPoint = LatLng(responder.latitude, responder.longitude);
        final centre = LatLng(
          (victim.latitude + responderPoint.latitude) / 2,
          (victim.longitude + responderPoint.longitude) / 2,
        );
        final distanceM = Geolocator.distanceBetween(
          victim.latitude,
          victim.longitude,
          responderPoint.latitude,
          responderPoint.longitude,
        );
        _emergencyMapController.move(centre, _emergencyZoom(distanceM));
      } catch (_) {
        // The embedded map may not be mounted yet during the first refresh.
      }
    });
  }

  Widget _buildEmergencyActiveCard(AlertRecord latest) {
    final active = latest.isActive;
    final responder = _primaryResponder;
    final victimPoint = _victimMapPoint(latest);
    final responderPoint = responder == null ? null : LatLng(responder.latitude, responder.longitude);
    final responderUpdated = responder?.updatedAt.toLocal();

    final mapCenter = responderPoint == null
        ? victimPoint
        : LatLng(
            (victimPoint.latitude + responderPoint.latitude) / 2,
            (victimPoint.longitude + responderPoint.longitude) / 2,
          );
    final mapDistance = responderPoint == null
        ? 0.0
        : Geolocator.distanceBetween(
            victimPoint.latitude,
            victimPoint.longitude,
            responderPoint.latitude,
            responderPoint.longitude,
          );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: active ? ViraColors.dangerSoft : ViraColors.lilac,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: active ? ViraColors.pink.withValues(alpha: .20) : ViraColors.lilacStrong,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87),
                    children: [
                      const TextSpan(text: 'Emergency '),
                      TextSpan(
                        text: latest.state.toUpperCase(),
                        style: TextStyle(color: active ? ViraColors.pinkDark : ViraColors.plum),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                latest.deliveryState,
                style: const TextStyle(fontWeight: FontWeight.w900, color: ViraColors.plum),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${latest.acknowledgedCount}/${latest.recipients.length} acknowledged  ·  '
            '${latest.deliveredCount}/${latest.recipients.length} delivered',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (active) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 245,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: FlutterMap(
                        mapController: _emergencyMapController,
                        options: MapOptions(
                          initialCenter: mapCenter,
                          initialZoom: responderPoint == null ? 15.8 : _emergencyZoom(mapDistance),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.viranari.viranari_app',
                          ),
                          if (_homeVictimTrail.length > 1)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _homeVictimTrail
                                      .map((p) => LatLng(p.latitude, p.longitude))
                                      .toList(growable: false),
                                  strokeWidth: 4,
                                  color: ViraColors.pinkDark,
                                ),
                              ],
                            ),
                          if (_homeResponderTrail.length > 1)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _homeResponderTrail
                                      .map((p) => LatLng(p.latitude, p.longitude))
                                      .toList(growable: false),
                                  strokeWidth: 5,
                                  color: const Color(0xFF2563EB),
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: victimPoint,
                                width: 92,
                                height: 80,
                                child: const _EmergencyMapMarker(
                                  label: 'Victim',
                                  icon: Icons.location_on_rounded,
                                  color: ViraColors.pinkDark,
                                ),
                              ),
                              if (responderPoint != null)
                                Marker(
                                  point: responderPoint,
                                  width: 110,
                                  height: 80,
                                  child: _EmergencyMapMarker(
                                    label: responder?.responderName ?? 'Responder',
                                    icon: Icons.directions_car_filled_rounded,
                                    color: const Color(0xFF2563EB),
                                  ),
                                ),
                            ],
                          ),
                          RichAttributionWidget(
                            attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Material(
                        color: Colors.white.withValues(alpha: .94),
                        borderRadius: BorderRadius.circular(14),
                        elevation: 2,
                        child: IconButton(
                          tooltip: 'Fit victim and responder',
                          onPressed: _fitEmergencyMap,
                          icon: const Icon(Icons.gps_fixed_rounded, color: ViraColors.plum),
                        ),
                      ),
                    ),
                    if (responder != null)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                          ),
                          child: Text(
                            '${_responderDistance(responder.distanceM)} · ETA ${_responderEta(responder.etaSeconds)}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .82),
                borderRadius: BorderRadius.circular(16),
              ),
              child: responder == null
                  ? const Row(
                      children: [
                        Icon(Icons.hourglass_top_rounded, color: ViraColors.warning),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Waiting for a trusted contact to accept and share responder GPS.',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.directions_car_filled_rounded, color: Color(0xFF2563EB)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${responder.responderName} → Victim  •  '
                                '${_responderDistance(responder.distanceM)} away  •  '
                                'ETA ${_responderEta(responder.etaSeconds)}',
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Responder GPS: ${responder.latitude.toStringAsFixed(5)}, ${responder.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(fontSize: 11, color: ViraColors.mutedPlum),
                        ),
                        Text(
                          'Victim GPS: ${victimPoint.latitude.toStringAsFixed(5)}, ${victimPoint.longitude.toStringAsFixed(5)}'
                          '${responderUpdated == null ? '' : '  ·  Updated ${DateFormat('h:mm:ss a').format(responderUpdated)}'}',
                          style: const TextStyle(fontSize: 11, color: ViraColors.mutedPlum),
                        ),
                        if (_responders.length > 1) ...[
                          const SizedBox(height: 4),
                          Text(
                            '+${_responders.length - 1} more trusted responder${_responders.length == 2 ? '' : 's'} active',
                            style: const TextStyle(fontSize: 11, color: ViraColors.gold, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _resolveSafe,
                    child: const Text("I'm safe"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: _cancelFalseAlarm,
                    child: const Text('False alarm'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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
    if (mounted) {
      setState(() {
        _latest = updated;
        _message = 'Emergency ended. The session remains in history.';
      });
    }
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
    if (mounted) {
      setState(() {
        _latest = updated;
        _message = 'False alarm cancelled. The record remains in history.';
      });
    }
  }

  String _fmt(DateTime? time) => time == null ? 'waiting' : DateFormat('h:mm:ss a').format(time.toLocal());

  String get _livenessLabel {
    if (_latest?.isActive != true) return 'READY';
    final seen = _latest?.lastDeviceSeenAt?.toLocal() ?? _lastHeartbeatAt;
    if (seen == null) return _backendOnline ? 'CONNECTING' : 'OFFLINE';
    final age = DateTime.now().difference(seen);
    if (age.inSeconds < 20) return 'LIVE';
    if (age.inSeconds < 60) return 'DELAYED';
    return 'OFFLINE';
  }

  Color get _livenessColor {
    switch (_livenessLabel) {
      case 'LIVE':
        return ViraColors.success;
      case 'DELAYED':
      case 'CONNECTING':
        return ViraColors.warning;
      case 'OFFLINE':
        return ViraColors.pinkDark;
      default:
        return ViraColors.plum;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _latest?.isActive == true;
    final latest = _latest;
    final silentActive = active && latest?.silentMode == true && !_silentRevealed;
    final stealthMode = _silentArming || silentActive;
    final lowBattery = (_battery ?? 100) <= 20;

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshDeviceStatus();
        await _refreshContacts();
        await _refreshLatest();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 110),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live Safety',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: ViraColors.plum,
                          ),
                    ),
                    const Text(
                      'One action. Stay visible to the people you trust.',
                      style: TextStyle(color: ViraColors.mutedPlum),
                    ),
                  ],
                ),
              ),
              Switch(value: _testMode, onChanged: active ? null : (v) => setState(() => _testMode = v)),
              const Text('Test'),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip(
                label: _backendOnline ? 'Server online' : 'Server offline',
                icon: Icons.cloud_outlined,
                good: _backendOnline,
              ),
              StatusChip(
                label: _network.toUpperCase(),
                icon: Icons.signal_cellular_alt,
                good: _network != 'offline',
              ),
              StatusChip(
                label: '${_battery ?? '--'}% battery',
                icon: Icons.battery_5_bar,
                good: !lowBattery,
              ),
              StatusChip(
                label: '$_trustedCount trusted',
                icon: Icons.group_outlined,
                good: _trustedCount > 0,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openSafetyMap,
                  icon: const Icon(Icons.public_rounded),
                  label: const Text('Safety Map'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openSafetyCompass,
                  icon: const Icon(Icons.explore_rounded),
                  label: const Text('Compass'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: SosButton(
              onPressed: silentActive ? _revealSilentSession : active ? null : () => _sendSos(),
              busy: _busy && !_silentArming,
              label: _testMode ? 'HOLD TEST SOS' : null,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            stealthMode
                ? 'Press and hold. No typing required.'
                : active
                    ? 'SOS ACTIVE — live location sharing continues'
                    : 'Press and hold. No typing required.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: active && !stealthMode ? ViraColors.pinkDark : ViraColors.plum,
            ),
          ),
          if (!stealthMode) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: active ? ViraColors.dangerSoft : ViraColors.surface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(_message, style: const TextStyle(height: 1.4, fontWeight: FontWeight.w700)),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.my_location, color: ViraColors.plum),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Live location',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      _livenessLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _livenessColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _MetricRow(label: 'Device heartbeat', value: _fmt(_latest?.lastDeviceSeenAt ?? _lastHeartbeatAt), good: _livenessLabel == 'LIVE'),
                _MetricRow(label: 'Phone GPS fix', value: _fmt(_lastPhoneFix), good: _lastPhoneFix != null),
                _MetricRow(label: 'Server location sync', value: _fmt(_lastServerSync), good: _lastServerSync != null && _syncError == null),
                _MetricRow(label: 'Queued GPS points', value: '$_queuedLocations', good: _queuedLocations == 0),
                if (_lastPosition != null)
                  _MetricRow(
                    label: 'GPS accuracy',
                    value: '±${_lastPosition!.accuracy.toStringAsFixed(0)} m',
                    good: _lastPosition!.accuracy < 30,
                  ),
                if (_lastPosition != null || _latest != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    'GPS: ${(_lastPosition?.latitude ?? _latest!.latitude).toStringAsFixed(6)}, ${(_lastPosition?.longitude ?? _latest!.longitude).toStringAsFixed(6)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: ViraColors.plum),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _openCurrentMap,
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open map'),
                  ),
                ],
                if (_syncError != null) ...[
                  const SizedBox(height: 8),
                  Text(_syncError!, style: const TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w800)),
                ],
                if (active && !_backgroundAlways) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'For strongest background tracking, enable “Allow all the time” location permission.',
                          style: TextStyle(color: ViraColors.warning),
                        ),
                      ),
                      TextButton(onPressed: _location.openAppSettings, child: const Text('Settings')),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (_pending > 0) ...[
            const SizedBox(height: 12),
            Text(
              '$_pending SOS request${_pending == 1 ? '' : 's'} waiting for server reconciliation.',
              style: const TextStyle(color: ViraColors.warning, fontWeight: FontWeight.w800),
            ),
          ],
          if (latest != null && !stealthMode) ...[
            const SizedBox(height: 14),
            _buildEmergencyActiveCard(latest),
          ],
        ],
      ),
    );
  }
}

class _EmergencyMapMarker extends StatelessWidget {
  const _EmergencyMapMarker({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .96),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)],
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color),
          ),
        ),
        Icon(icon, size: 34, color: color, shadows: const [Shadow(blurRadius: 5, color: Colors.white)]),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value, required this.good});
  final String label;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            good ? Icons.check_circle : Icons.schedule,
            size: 17,
            color: good ? ViraColors.success : ViraColors.warning,
          ),
          const SizedBox(width: 7),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
