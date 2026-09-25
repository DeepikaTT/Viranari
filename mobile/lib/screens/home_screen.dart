import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
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
  final _queue = OfflineQueueService();
  bool _busy = false;
  int _pending = 0;
  String _message = 'Ready. Press and hold SOS when you need help.';
  AlertRecord? _latest;

  @override
  void initState() {
    super.initState();
    _refreshQueue();
    _retryPending();
  }

  Future<void> _refreshQueue() async {
    final count = await _queue.count();
    if (mounted) setState(() => _pending = count);
  }

  Future<void> _retryPending() async {
    final resolved = await _queue.flush(widget.session.api);
    if (resolved > 0 && mounted) {
      setState(() => _message = '$resolved queued SOS request${resolved == 1 ? '' : 's'} safely reconciled.');
    }
    await _refreshQueue();
  }

  Future<void> _sendSos() async {
    if (_busy) return;
    await HapticFeedback.heavyImpact();
    setState(() {
      _busy = true;
      _message = 'Getting your GPS location…';
    });

    QueuedAlert? payload;
    try {
      final position = await _location.current();
      payload = QueuedAlert(
        idempotencyKey: const Uuid().v4(),
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
        note: 'Emergency SOS from ViraNari mobile app',
      );

      if (mounted) setState(() => _message = 'Sending SOS to your trusted circle…');
      final alert = await widget.session.api.sendAlert(payload);
      if (mounted) {
        setState(() {
          _latest = alert;
          _message = alert.recipients.isEmpty
              ? 'SOS recorded, but no active trusted contacts are connected yet.'
              : 'SOS sent. Waiting for a trusted contact to receive it.';
        });
      }
    } on ApiException catch (e) {
      if (payload != null) {
        // We intentionally queue even after a timeout: on retry we first ask
        // the backend whether this idempotency key already arrived.
        await _queue.enqueue(payload);
        if (mounted) setState(() => _message = '${e.message}. SOS saved to offline queue; ViraNari will reconcile it on retry.');
      } else if (mounted) {
        setState(() => _message = e.message);
      }
    } catch (e) {
      if (payload != null) {
        await _queue.enqueue(payload);
        if (mounted) setState(() => _message = 'Network unavailable. SOS saved locally for safe retry.');
      } else if (mounted) {
        setState(() => _message = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      await _refreshQueue();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshLatest() async {
    if (_latest == null) {
      await _retryPending();
      return;
    }
    try {
      final refreshed = await widget.session.api.getAlert(_latest!.id);
      if (mounted) {
        setState(() {
          _latest = refreshed;
          _message = refreshed.deliveryState == 'Acknowledged'
              ? 'Help request acknowledged by a trusted contact.'
              : refreshed.deliveryState == 'Delivered'
                  ? 'SOS delivered. Waiting for acknowledgement.'
                  : _message;
        });
      }
    } catch (_) {}
    await _retryPending();
  }

  @override
  Widget build(BuildContext context) {
    final state = _latest?.deliveryState;
    return RefreshIndicator(
      onRefresh: _refreshLatest,
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
                    const Text('Your emergency dashboard', style: TextStyle(color: ViraColors.mutedPlum)),
                  ],
                ),
              ),
              IconButton.filledTonal(onPressed: _refreshLatest, icon: const Icon(Icons.sync_rounded), tooltip: 'Retry queued SOS and refresh status'),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: ViraColors.lilac, borderRadius: BorderRadius.circular(24)),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const StatusChip(label: 'GPS on trigger', icon: Icons.my_location),
                StatusChip(label: _pending == 0 ? 'Queue clear' : '$_pending queued', icon: _pending == 0 ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, good: _pending == 0),
                StatusChip(label: state ?? 'Standby', icon: state == 'Acknowledged' ? Icons.verified_user_outlined : Icons.shield_outlined, good: state == 'Acknowledged'),
              ],
            ),
          ),
          const SizedBox(height: 34),
          Center(child: SosButton(onPressed: _busy ? null : _sendSos, busy: _busy)),
          const SizedBox(height: 28),
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
                Icon(state == 'Acknowledged' ? Icons.check_circle : Icons.info_outline, color: state == 'Acknowledged' ? ViraColors.success : ViraColors.plum),
                const SizedBox(width: 12),
                Expanded(child: Text(_message, style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          if (_latest != null) ...[
            const SizedBox(height: 16),
            _LatestAlertCard(alert: _latest!),
          ],
          const SizedBox(height: 18),
          const Text(
            'ViraNari never shows “delivered” until a trusted contact app actually retrieves the alert from the server, and never shows “acknowledged” until that person confirms it.',
            style: TextStyle(color: ViraColors.mutedPlum, height: 1.45),
          ),
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
          const Text('Latest SOS', style: TextStyle(fontWeight: FontWeight.w900, color: ViraColors.plum, fontSize: 17)),
          const SizedBox(height: 8),
          Text('${alert.latitude.toStringAsFixed(5)}, ${alert.longitude.toStringAsFixed(5)}', style: const TextStyle(color: ViraColors.mutedPlum)),
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
                    Text(r.acknowledgedAt != null ? 'ACKNOWLEDGED' : r.deliveredAt != null ? 'DELIVERED' : 'SENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: r.acknowledgedAt != null ? ViraColors.success : ViraColors.mutedPlum)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
