import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import 'safe_reach_sheet.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.session});
  final AppSession session;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<AlertRecord> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.session.api.history();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showIncident(AlertRecord alert) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: ViraColors.surface,
      showDragHandle: true,
      builder: (_) => SafeReachSheet(session: widget.session, alertId: alert.id, canRematch: alert.isActive),
    );
    await _load();
  }

  Color _stateColor(AlertRecord alert) {
    if (alert.state == 'resolved') return ViraColors.success;
    if (alert.state == 'cancelled') return ViraColors.mutedPlum;
    if (alert.deliveryState == 'Acknowledged') return ViraColors.success;
    if (alert.deliveryState == 'Delivered') return ViraColors.warning;
    return ViraColors.pinkDark;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
        children: [
          Text('SOS History', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: ViraColors.plum)),
          const SizedBox(height: 6),
          const Text('Persistent emergency sessions, latest location and delivery receipts.', style: TextStyle(color: ViraColors.mutedPlum)),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: ViraColors.pinkDark))
          else if (_items.isEmpty)
            const Text('No SOS events yet.')
          else
            ..._items.map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 10, height: 56, decoration: BoxDecoration(color: _stateColor(a), borderRadius: BorderRadius.circular(99))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text('${a.state.toUpperCase()} · ${a.deliveryState}', style: TextStyle(fontWeight: FontWeight.w900, color: _stateColor(a)))),
                                Text(DateFormat('dd MMM, h:mm a').format(a.createdAt.toLocal()), style: const TextStyle(color: ViraColors.mutedPlum, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text('${a.latitude.toStringAsFixed(5)}, ${a.longitude.toStringAsFixed(5)}'),
                            const SizedBox(height: 2),
                            Text('${a.acknowledgedCount}/${a.recipients.length} acknowledged · last update ${DateFormat('h:mm:ss a').format(a.updatedAt.toLocal())}', style: const TextStyle(color: ViraColors.mutedPlum, fontSize: 12)),
                            if (a.safeReach != null) ...[
                              const SizedBox(height: 4),
                              Text('SafeReach · ${a.safeReach!.organizationName} · ${a.safeReach!.statusLabel}', style: const TextStyle(color: ViraColors.success, fontSize: 12, fontWeight: FontWeight.w800)),
                            ],
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => _showIncident(a),
                              icon: const Icon(Icons.verified_user_outlined, size: 18),
                              label: const Text('Incident proof & responder'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
