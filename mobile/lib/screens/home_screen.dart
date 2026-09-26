import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
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
import 'safe_reach_sheet.dart';

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

  bool _busy = false;
  bool _backendOnline = false;
  bool _sendingLiveUpdate = false;
  bool _testMode = false;
  bool _backgroundAlways = false;
  bool _heartbeatRunning = false;
  bool _recoveryRunning = false;

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
  DateTime? _lastSafeReachSearchAt;
  Position? _lastPosition;
  AlertRecord? _latest;

  StreamSubscription<Position>? _liveLocationSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
          if (active.safeReach == null) _lastSafeReachSearchAt = DateTime.now();
          _message = 'Emergency session restored. Live tracking resumed.';
        });
        await _startLiveTracking(active.id);
      }
    } catch (_) {
      // The local UI remains usable even if the backend is temporarily offline.
    }
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
        final safeReachNeedsRetry = refreshed.safeReach == null ||
            refreshed.safeReach!.state == 'declined' ||
            refreshed.safeReach!.state == 'expired';
        final now = DateTime.now();
        final retryAge = _lastSafeReachSearchAt == null ? const Duration(days: 1) : now.difference(_lastSafeReachSearchAt!);
        if (safeReachNeedsRetry && retryAge >= const Duration(seconds: 30)) {
          _lastSafeReachSearchAt = now;
          try {
            final rematched = await widget.session.api.rematchSafeReach(active.id);
            if (mounted) setState(() => _latest = rematched);
          } catch (_) {
            // Trusted Circle + live tracking remain primary even when no responder is available.
          }
        }
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
          _backendOnline = true;
          if (alert.safeReach == null) _lastSafeReachSearchAt = DateTime.now();
          _message = alert.isTest
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshLatest({bool silent = false}) async {
    if (_latest == null || !_backendOnline) return;
    try {
      final refreshed = await widget.session.api.getAlert(_latest!.id);
      if (!mounted) return;
      setState(() {
        _latest = refreshed;
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

  Future<void> _showSafeReach() async {
    final alert = _latest;
    if (alert == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: ViraColors.surface,
      showDragHandle: true,
      builder: (_) => SafeReachSheet(session: widget.session, alertId: alert.id, canRematch: true),
    );
    await _refreshLatest();
  }

  Future<void> _callEmergencyServices() async {
    const emergencyNumber = String.fromEnvironment('VIRANARI_EMERGENCY_NUMBER', defaultValue: '112');
    final opened = await launchUrl(Uri(scheme: 'tel', path: emergencyNumber), mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the phone app.')));
    }
  }

  Future<void> _callTrustedContact() async {
    try {
      final contacts = await widget.session.api.contacts();
      final callable = contacts.where((c) => c.status == 'active' && c.phoneE164 != null && c.phoneE164!.isNotEmpty).toList();
      if (callable.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No accepted Trusted Circle contact has a phone number yet.')),
          );
        }
        return;
      }
      final phone = callable.first.phoneE164!;
      final opened = await launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the phone app.')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
    final state = _latest?.deliveryState;
    final active = _latest?.isActive == true;
    final batteryText = _battery == null ? 'Battery ?' : 'Battery $_battery%';

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshDeviceStatus();
        await _refreshContacts();
        await _refreshLatest();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hi ${widget.session.user?.name ?? ''}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: ViraColors.plum)),
                    const SizedBox(height: 4),
                    Text(active ? 'Emergency response mode' : 'Ready when seconds matter', style: const TextStyle(color: ViraColors.mutedPlum)),
                  ],
                ),
              ),
              IconButton.filledTonal(onPressed: () => _refreshLatest(), icon: const Icon(Icons.sync_rounded), tooltip: 'Refresh emergency status'),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: active ? ViraColors.dangerSoft : ViraColors.lilac,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: active ? ViraColors.pinkDark.withValues(alpha: .35) : ViraColors.lilacStrong),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusChip(label: _backendOnline ? 'Server reachable' : 'Server offline', icon: _backendOnline ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, good: _backendOnline),
                StatusChip(label: _network.toUpperCase(), icon: _network == 'offline' ? Icons.signal_wifi_off : Icons.network_check, good: _network != 'offline' && _network != 'unknown'),
                StatusChip(label: batteryText, icon: Icons.battery_5_bar, good: (_battery ?? 100) > 20),
                StatusChip(label: '$_trustedCount trusted', icon: Icons.group_outlined, good: _trustedCount > 0),
                StatusChip(label: _pending == 0 ? 'Queue clear' : '$_pending queued', icon: _pending == 0 ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, good: _pending == 0),
              ],
            ),
          ),
          const SizedBox(height: 28),
          if (active) _ActiveEmergencyBanner(alert: _latest!),
          if (active) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _showSafeReach,
                    icon: const Icon(Icons.verified_user_rounded),
                    label: Text(_latest?.safeReach == null ? 'SafeReach' : _latest!.safeReach!.statusLabel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _callTrustedContact,
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('Call trusted'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: ViraColors.pinkDark),
                onPressed: _callEmergencyServices,
                icon: const Icon(Icons.local_police_outlined),
                label: const Text('Call emergency services'),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (!active) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: _testMode ? ViraColors.lilac : Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: ViraColors.lilacStrong)),
              child: Row(
                children: [
                  const Icon(Icons.science_outlined, color: ViraColors.plum),
                  const SizedBox(width: 10),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Practice mode', style: TextStyle(fontWeight: FontWeight.w900)), Text('Send a clearly labelled test alert to verify your setup.', style: TextStyle(color: ViraColors.mutedPlum, fontSize: 12))])),
                  Switch(value: _testMode, onChanged: (value) => setState(() => _testMode = value)),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          Center(child: SosButton(onPressed: (_busy || active) ? null : _sendSos, busy: _busy, label: _testMode ? 'HOLD TO TEST' : 'HOLD FOR HELP')), 
          const SizedBox(height: 12),
          Center(
            child: Text(
              active ? 'SOS already active — live location is being shared' : 'Press and hold. No typing required.',
              style: const TextStyle(color: ViraColors.mutedPlum, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ViraColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ViraColors.lilacStrong),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.sms_outlined, color: ViraColors.plum),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SMS fallback — coming next', style: TextStyle(fontWeight: FontWeight.w900, color: ViraColors.plum)),
                      SizedBox(height: 3),
                      Text('Placeholder only in this build. No SMS permission is requested and no message is sent yet.', style: TextStyle(color: ViraColors.mutedPlum, height: 1.35)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if ((_battery ?? 100) <= 20) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFFFF1D9), borderRadius: BorderRadius.circular(18)),
              child: const Row(children: [Icon(Icons.battery_alert_rounded, color: ViraColors.warning), SizedBox(width: 10), Expanded(child: Text('Low battery: keep the emergency active, reduce nonessential screen use, and move toward a safe public place if possible.', style: TextStyle(fontWeight: FontWeight.w700)))]),
            ),
          ],
          const SizedBox(height: 24),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: state == 'Acknowledged' ? ViraColors.successSoft : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: state == 'Acknowledged' ? ViraColors.success : ViraColors.lilacStrong),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(state == 'Acknowledged' ? Icons.check_circle : active ? Icons.crisis_alert : Icons.info_outline, color: state == 'Acknowledged' ? ViraColors.success : active ? ViraColors.pinkDark : ViraColors.plum),
                const SizedBox(width: 12),
                Expanded(child: Text(_message, style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          if (_latest != null) ...[
            const SizedBox(height: 16),
            _LatestAlertCard(alert: _latest!),
          ],
          if (active) ...[
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: _resolveSafe, icon: const Icon(Icons.health_and_safety_outlined), label: const Text("I'm safe — end emergency")),
            const SizedBox(height: 6),
            TextButton(onPressed: _cancelFalseAlarm, child: const Text('Accidental trigger? Cancel false alarm')),
          ],
          const SizedBox(height: 18),
          const Text(
            'ViraNari distinguishes SENT, DELIVERED and ACKNOWLEDGED. During an active session it keeps updating the latest location instead of assuming the first GPS point is enough.',
            style: TextStyle(color: ViraColors.mutedPlum, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _ActiveEmergencyBanner extends StatelessWidget {
  const _ActiveEmergencyBanner({required this.alert});
  final AlertRecord alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ViraColors.midnight,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: ViraColors.midnight.withValues(alpha: .18), blurRadius: 28, offset: const Offset(0, 12))],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(color: ViraColors.pink, shape: BoxShape.circle),
            child: const Icon(Icons.sensors_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alert.isTest ? 'TEST DRILL ACTIVE' : 'EMERGENCY ACTIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text('Live update ${DateFormat('h:mm:ss a').format(alert.updatedAt.toLocal())}', style: const TextStyle(color: Color(0xFFD4E5E4))),
              ],
            ),
          ),
          const Icon(Icons.location_searching, color: ViraColors.gold),
        ],
      ),
    );
  }
}

class _LatestAlertCard extends StatelessWidget {
  const _LatestAlertCard({required this.alert});
  final AlertRecord alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Latest SOS', style: TextStyle(fontWeight: FontWeight.w900, color: ViraColors.plum, fontSize: 17))),
              if (alert.isTest) const Padding(padding: EdgeInsets.only(right: 8), child: Text('TEST', style: TextStyle(color: ViraColors.gold, fontWeight: FontWeight.w900, fontSize: 11))),
              Text(alert.state.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: alert.isActive ? ViraColors.pinkDark : ViraColors.mutedPlum)),
            ],
          ),
          const SizedBox(height: 8),
          Text('${alert.latitude.toStringAsFixed(5)}, ${alert.longitude.toStringAsFixed(5)}', style: const TextStyle(color: ViraColors.mutedPlum)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            children: [
              if (alert.batteryPercent != null) Text('Battery ${alert.batteryPercent}%', style: const TextStyle(color: ViraColors.mutedPlum)),
              if (alert.networkState != null) Text(alert.networkState!.toUpperCase(), style: const TextStyle(color: ViraColors.mutedPlum)),
            ],
          ),
          const SizedBox(height: 12),
          if (alert.recipients.isEmpty)
            const Text('No active trusted contacts.', style: TextStyle(fontWeight: FontWeight.w700))
          else
            ...alert.recipients.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(r.acknowledgedAt != null ? Icons.check_circle : r.deliveredAt != null ? Icons.mark_email_read_outlined : Icons.schedule_send_outlined, size: 20, color: r.acknowledgedAt != null ? ViraColors.success : ViraColors.plum),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text(r.acknowledgedAt != null ? 'ACKNOWLEDGED' : r.deliveredAt != null ? 'DELIVERED' : 'SENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: r.acknowledgedAt != null ? ViraColors.success : ViraColors.mutedPlum)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
