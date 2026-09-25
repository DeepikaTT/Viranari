import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.session});
  final AppSession session;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<InboxAlert> _items = const [];
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
      final data = await widget.session.api.inbox();
      if (mounted) setState(() => _items = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ack(InboxAlert item) async {
    await widget.session.api.acknowledge(item.alertId);
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Acknowledgement sent to the person who triggered SOS.')));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
        children: [
          Text('Emergency Inbox', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: ViraColors.plum)),
          const SizedBox(height: 6),
          const Text('Pull to refresh. Opening this inbox counts as server-confirmed delivery.', style: TextStyle(color: ViraColors.mutedPlum)),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: ViraColors.pinkDark))
          else if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: ViraColors.lilac, borderRadius: BorderRadius.circular(24)),
              child: const Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 44, color: ViraColors.plum),
                  SizedBox(height: 10),
                  Text('No emergency alerts', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                ],
              ),
            )
          else
            ..._items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    color: item.acknowledgedAt != null ? ViraColors.successSoft : ViraColors.dangerSoft,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(item.acknowledgedAt != null ? Icons.check_circle : Icons.crisis_alert_rounded, color: item.acknowledgedAt != null ? ViraColors.success : ViraColors.pinkDark),
                          const SizedBox(width: 9),
                          Expanded(child: Text('${item.senderName} needs help', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(DateFormat('dd MMM, h:mm a').format(item.createdAt.toLocal()), style: const TextStyle(color: ViraColors.mutedPlum)),
                      const SizedBox(height: 4),
                      SelectableText('GPS: ${item.latitude.toStringAsFixed(5)}, ${item.longitude.toStringAsFixed(5)}'),
                      if (item.note != null) ...[
                        const SizedBox(height: 4),
                        Text(item.note!),
                      ],
                      const SizedBox(height: 12),
                      if (item.acknowledgedAt == null)
                        FilledButton.icon(onPressed: () => _ack(item), icon: const Icon(Icons.volunteer_activism), label: const Text('I received this — acknowledge'))
                      else
                        const Text('Acknowledged', style: TextStyle(color: ViraColors.success, fontWeight: FontWeight.w900)),
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
