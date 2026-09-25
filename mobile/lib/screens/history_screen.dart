import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';

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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
        children: [
          Text('SOS History', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: ViraColors.plum)),
          const SizedBox(height: 5),
          const Text('A factual timeline of emergency sessions and delivery state.', style: TextStyle(color: ViraColors.mutedPlum)),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: ViraColors.pinkDark))
          else if (_items.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: Text('No SOS events yet.')))
          else
            ..._items.map((a) => Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(width: 8, height: 44, decoration: BoxDecoration(color: _stateColor(a), borderRadius: BorderRadius.circular(99))),
                      title: Text('${a.state.toUpperCase()} · ${a.deliveryState}', style: TextStyle(fontWeight: FontWeight.w900, color: _stateColor(a))),
                      subtitle: Text('${DateFormat('dd MMM, h:mm a').format(a.createdAt.toLocal())} · ${a.acknowledgedCount}/${a.recipients.length} acknowledged\n${a.latitude.toStringAsFixed(5)}, ${a.longitude.toStringAsFixed(5)}'),
                      isThreeLine: true,
                    ),
                    const Divider(height: 1),
                  ],
                )),
        ],
      ),
    );
  }
}
