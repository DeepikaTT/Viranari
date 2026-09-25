import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../services/device_status_service.dart';
import '../services/location_service.dart';
import '../services/offline_queue.dart';
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

  bool _busy = false;
  bool _backendOnline = false;
  bool _sendingLiveUpdate = false;
  bool _testMode = false;
  int _pending = 0;
  int _trustedCount = 0;
  int? _battery;
  String _network = 'checking';
  String _message = 'Ready. Press and hold SOS when you need help.';
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
          _message = 'Emergency session restored. Live location sharing is active.';
        });
        await _startLiveTracking(active.id);
      }
    } catch (_) {}
  }

  Future<void> _heartbeat() async {
    await _refreshDeviceStatus();
    await _retryPending();
    if (_latest != null) await _refreshLatest(silent: true);
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
      if (mounted) setState(() => _trustedCount = contacts.where((c) => c.status == 'active').length);
    } catch (_) {}
  }

  Future<void> _refreshQueue() async {
    final count = await _queue.count();
    if (mounted) setState(() => _pending = count);
  }

  Future<void> _retryPending() async {
    final resolved = await _queue.flush(widget.session.api);
    if (resolved > 0) {
      try {
        final active = await widget.session.api.activeAlert();
        if (mounted && active != null) {
          setState(() {
            _latest = active;
            _message = '$resolved queued SOS request${resolved == 1 ? '' : 's'} reconciled. Emergency session is active.';
          });
          await _startLiveTracking(active.id);
        }
      } catch (_) {}
    }
    await _refreshQueue();
  }

  Future<void> _startLiveTracking(String alertId) async {
    if (_liveLocationSubscription != null) return;
    try {
      final stream = await _location.liveStream();
      _liveLocationSubscription = stream.listen((position) async {
        if (_sendingLiveUpdate) return;
        _sendingLiveUpdate = true;
        try {
          final snapshot = await _device.snapshot();
          final updated = await widget.session.api.updateLocation(
            alertId,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyM: position.accuracy,
            batteryPercent: snapshot.batteryPercent,
            networkState: snapshot.networkState,
          );
          if (mounted) {
            setState(() {
              _latest = updated;
              _battery = snapshot.batteryPercent;
              _network = snapshot.networkState;
            });
          }
        } catch (_) {
          // Do not stop an emergency because one live update failed. The next
          // GPS sample retries naturally while the original SOS remains stored.
        } finally {
          _sendingLiveUpdate = false;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _message = '${_cleanError(e)} The SOS itself remains active.');
    }
  }

  Future<void> _stopLiveTracking() async {
    await _liveLocationSubscription?.cancel();
    _liveLocationSubscription = null;
  }

  String _cleanError(Object e) => e.toString().replaceFirst('Bad state: ', '');

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
        isTest: _testMode,
        note: _testMode ? 'ViraNari TEST DRILL — no real emergency' : 'Emergency SOS from ViraNari mobile app',
      );

      if (mounted) setState(() => _message = 'Sending SOS to your trusted circle…');
      final alert = await widget.session.api.sendAlert(payload);
      if (mounted) {
        setState(() {
          _latest = alert;
          _battery = snapshot.batteryPercent;
          _network = snapshot.networkState;
          _message = alert.isTest
              ? 'Test drill is active. Trusted contacts will see a TEST label.'
              : alert.recipients.isEmpty
                  ? 'SOS is active, but no trusted contacts are connected. Keep moving toward a safer public place if you can.'
                  : 'SOS is active. ${alert.recipients.length} trusted contact${alert.recipients.length == 1 ? '' : 's'} notified on the ViraNari server.';
        });
      }
      await _startLiveTracking(alert.id);
    } on ApiException catch (e) {
      if (payload != null) {
        await _queue.enqueue(payload);
        if (mounted) setState(() => _message = '${e.message}. SOS saved to the encrypted retry queue.');
      } else if (mounted) {
        setState(() => _message = e.message);
      }
    } catch (e) {
      if (payload != null) {
        await _queue.enqueue(payload);
        if (mounted) setState(() => _message = 'Network unavailable. SOS saved locally for safe retry.');
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
    if (_latest == null) {
      await _retryPending();
      return;
    }
    try {
      final refreshed = await widget.session.api.getAlert(_latest!.id);
      if (!mounted) return;
      setState(() {
        _latest = refreshed;
        if (!silent) {
          _message = refreshed.deliveryState == 'Acknowledged'
              ? '${refreshed.acknowledgedCount} trusted contact${refreshed.acknowledgedCount == 1 ? '' : 's'} acknowledged your SOS.'
              : refreshed.deliveryState == 'Delivered'
                  ? 'SOS delivered to ${refreshed.deliveredCount} trusted contact${refreshed.deliveredCount == 1 ? '' : 's'}. Waiting for acknowledgement.'
                  : refreshed.state == 'resolved'
                      ? 'Emergency session ended and saved to history.'
                      : refreshed.state == 'cancelled'
                          ? 'False alarm cancelled. The record remains in history.'
                          : _message;
        }
      });
      if (!refreshed.isActive) await _stopLiveTracking();
    } catch (_) {}
    await _retryPending();
  }

  Future<void> _resolveSafe() async {
    final alert = _latest;
    if (alert == null || !alert.isActive) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End emergency session?'),
        content: const Text('Use this only when you are safe. Your trusted contacts will see that the emergency ended.'),
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
      _message = 'Emergency ended. Your session remains in SOS history.';
    });
  }

  Future<void> _cancelFalseAlarm() async {
    final alert = _latest;
    if (alert == null || !alert.isActive) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel as false alarm?'),
        content: const Text('Only cancel if this was accidental. If you may still be unsafe, keep the emergency active.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep SOS active')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel false alarm')),
        ],
      ),
    );
    if (yes != true) return;
    final updated = await widget.session.api.cancelAlert(alert.id);
    await _stopLiveTracking();
    if (mounted) setState(() {
      _latest = updated;
      _message = 'False alarm cancelled. Trusted contacts can see the cancellation state.';
    });
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
          if (active) const SizedBox(height: 18),
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
