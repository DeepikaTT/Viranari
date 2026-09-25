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

  Color _stateColor(String state) {
    if (state == 'Acknowledged') return ViraColors.success;
    if (state == 'Delivered') return ViraColors.warning;
    return ViraColors.plum;
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
          const Text('Persistent server records and delivery receipts.', style: TextStyle(color: ViraColors.mutedPlum)),
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
                      Container(width: 10, height: 46, decoration: BoxDecoration(color: _stateColor(a.deliveryState), borderRadius: BorderRadius.circular(99))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(a.deliveryState, style: TextStyle(fontWeight: FontWeight.w900, color: _stateColor(a.deliveryState)))),
                                Text(DateFormat('dd MMM, h:mm a').format(a.createdAt.toLocal()), style: const TextStyle(color: ViraColors.mutedPlum, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text('${a.latitude.toStringAsFixed(5)}, ${a.longitude.toStringAsFixed(5)}'),
                            Text('${a.recipients.length} trusted contact${a.recipients.length == 1 ? '' : 's'}', style: const TextStyle(color: ViraColors.mutedPlum)),
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
