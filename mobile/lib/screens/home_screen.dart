import 'dart:async';

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
import '../widgets/status_chip.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final AppSession session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _location = LocationService();
  final _device = DeviceStatusService();
  final _queue = OfflineQueueService();
  final _phoneStore = TrustedPhoneStore();
  final _settings = SafetySettingsStore();
  final _sms = SmsFallbackService();
  final _locationSync = LocationSyncService();

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

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) => _heartbeat());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _liveLocationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _smsReady = await _settings.smsFallbackEnabled() && await _sms.isReady();
    await _refreshDeviceStatus();
    await _refreshQueue();
    await _retryPending();
    await _refreshContacts();
    try {
      final active = await widget.session.api.activeAlert();
      if (!mounted) return;
      if (active != null) {
        setState(() {
          _latest = active;
          _lastServerSync = active.updatedAt.toLocal();
          _message = 'Emergency session restored. Live Safety tracking is active.';
        });
        await _startLiveTracking(active.id);
      }
    } catch (_) {}
  }

  Future<void> _heartbeat() async {
    await _refreshDeviceStatus();
    await _retryPending();
    final active = _latest;
    if (active != null && active.isActive) {
      await _flushLocationQueue(active.id);
      await _refreshLatest(silent: true);
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
            _lastServerSync = active.updatedAt.toLocal();
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
      _liveLocationSubscription = stream.listen((position) async {
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
              _syncError = 'Server sync interrupted. GPS points are being queued securely.';
            });
          }
        } finally {
          _sendingLiveUpdate = false;
          await _refreshQueue();
        }
      }, onError: (Object e) {
        if (mounted) setState(() => _syncError = 'GPS stream error: ${_cleanError(e)}');
      });
    } catch (e) {
      if (mounted) setState(() => _message = '${_cleanError(e)} The SOS itself remains active.');
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
          _lastPhoneFix = DateTime.now();
          _lastServerSync = DateTime.now();
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
        _lastServerSync = refreshed.updatedAt.toLocal();
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
        content: Text(ready ? 'SMS fallback is prepared for emergencies.' : 'SMS permission was not granted.'),
      ));
    }
  }

  String _fmt(DateTime? time) => time == null ? 'waiting' : DateFormat('h:mm:ss a').format(time.toLocal());

  @override
  Widget build(BuildContext context) {
    final active = _latest?.isActive == true;
    final latest = _latest;
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
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Live Safety', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: ViraColors.plum)),
              const Text('One action. Multiple ways to keep help connected.', style: TextStyle(color: ViraColors.mutedPlum)),
            ])),
            Switch(value: _testMode, onChanged: active ? null : (v) => setState(() => _testMode = v)),
            const Text('Test'),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            StatusChip(label: _backendOnline ? 'Server online' : 'Server offline', icon: Icons.cloud_outlined, good: _backendOnline),
            StatusChip(label: _network.toUpperCase(), icon: Icons.signal_cellular_alt, good: _network != 'offline'),
            StatusChip(label: '${_battery ?? '--'}% battery', icon: Icons.battery_5_bar, good: !lowBattery),
            StatusChip(label: '$_trustedCount trusted', icon: Icons.group_outlined, good: _trustedCount > 0),
            StatusChip(label: _smsReady ? 'SMS ready' : 'SMS not ready', icon: Icons.sms_outlined, good: _smsReady),
          ]),
          const SizedBox(height: 18),
          Center(child: SosButton(onPressed: active ? null : _sendSos, busy: _busy, label: _testMode ? 'HOLD TEST SOS' : null)),
          const SizedBox(height: 14),
          Text(active ? 'SOS ACTIVE — location sharing continues' : 'Press and hold. No typing required.', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: ViraColors.plum)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: active ? ViraColors.dangerSoft : ViraColors.surface, borderRadius: BorderRadius.circular(22)),
            child: Text(_message, style: const TextStyle(height: 1.4, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.my_location, color: ViraColors.plum), SizedBox(width: 8), Text('Find-My-style tracking', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))]),
              const SizedBox(height: 12),
              _MetricRow(label: 'Phone GPS fix', value: _fmt(_lastPhoneFix), good: _lastPhoneFix != null),
              _MetricRow(label: 'Server synced', value: _fmt(_lastServerSync), good: _lastServerSync != null && _syncError == null),
              _MetricRow(label: 'Queued GPS points', value: '$_queuedLocations', good: _queuedLocations == 0),
              if (_lastPosition != null) _MetricRow(label: 'Accuracy', value: '±${_lastPosition!.accuracy.toStringAsFixed(0)} m', good: _lastPosition!.accuracy < 30),
              if (_syncError != null) ...[
                const SizedBox(height: 8),
                Text(_syncError!, style: const TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w800)),
              ],
              if (active && !_backgroundAlways) ...[
                const SizedBox(height: 10),
                Row(children: [
                  const Expanded(child: Text('Background permission may be limited. Tracking is strongest when “Allow all the time” is enabled.', style: TextStyle(color: ViraColors.warning))),
                  TextButton(onPressed: _location.openAppSettings, child: const Text('Settings')),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: ViraColors.successSoft, borderRadius: BorderRadius.circular(22)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.sms_outlined, color: ViraColors.success), SizedBox(width: 8), Text('SMS survival fallback', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))]),
              const SizedBox(height: 6),
              Text('$_trustedSmsCount cached trusted phone number${_trustedSmsCount == 1 ? '' : 's'}. SMS is used only if the API cannot be reached.', style: const TextStyle(color: ViraColors.mutedPlum)),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _smsReady,
                onChanged: active ? null : _configureSms,
                title: const Text('Prepare SMS fallback before danger', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Android can dispatch directly after permission. iPhone opens the Messages composer for user approval.'),
              ),
            ]),
          ),
          if (_pending > 0) ...[
            const SizedBox(height: 12),
            Text('$_pending SOS request${_pending == 1 ? '' : 's'} waiting for server reconciliation.', style: const TextStyle(color: ViraColors.warning, fontWeight: FontWeight.w800)),
          ],
          if (latest != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: ViraColors.lilac, borderRadius: BorderRadius.circular(22)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Emergency ${latest.state.toUpperCase()}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                  Text(latest.deliveryState, style: const TextStyle(fontWeight: FontWeight.w900, color: ViraColors.plum)),
                ]),
                const SizedBox(height: 6),
                Text('${latest.acknowledgedCount}/${latest.recipients.length} acknowledged · ${latest.deliveredCount}/${latest.recipients.length} delivered'),
                const SizedBox(height: 10),
                if (active) Row(children: [
                  Expanded(child: FilledButton.tonal(onPressed: _resolveSafe, child: const Text("I'm safe"))),
                  const SizedBox(width: 8),
                  Expanded(child: TextButton(onPressed: _cancelFalseAlarm, child: const Text('False alarm'))),
                ]),
              ]),
            ),
          ],
        ],
      ),
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
      child: Row(children: [
        Icon(good ? Icons.check_circle : Icons.schedule, size: 17, color: good ? ViraColors.success : ViraColors.warning),
        const SizedBox(width: 7),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
