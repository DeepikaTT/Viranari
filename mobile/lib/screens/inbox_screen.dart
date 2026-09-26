import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _firstLoad = true;
  String? _error;
  Timer? _pollTimer;
  Set<String> _knownIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await widget.session.api.inbox();
      final newActive = data.where((a) => a.isActive && !_knownIds.contains(a.alertId)).toList();
      final previousIds = _knownIds;
      _knownIds = data.map((e) => e.alertId).toSet();
      if (mounted) setState(() => _items = data);

      if (!_firstLoad && previousIds.isNotEmpty && newActive.isNotEmpty && mounted) {
        final newest = newActive.first;
        if (newest.isTest) {
          await HapticFeedback.selectionClick();
        } else {
          await HapticFeedback.heavyImpact();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(newest.isTest ? 'TEST DRILL from ${newest.senderName}.' : 'Emergency: ${newest.senderName} needs help. Open Inbox for live location.'),
          ),
        );
      }
      _firstLoad = false;
    } on ApiException catch (e) {
      if (mounted && !silent) setState(() => _error = e.message);
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _ack(InboxAlert item) async {
    await widget.session.api.acknowledge(item.alertId);
    await HapticFeedback.mediumImpact();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acknowledgement sent. Stay safe; do not confront danger alone.')),
      );
    }
  }

  Future<void> _openMap(InboxAlert item) async {
    final uri = Uri.parse('geo:${item.latitude},${item.longitude}?q=${item.latitude},${item.longitude}(ViraNari%20SOS)');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No map app could open this location.')));
    }
  }

  Future<void> _showTimeline(InboxAlert item) async {
    try {
      final points = await widget.session.api.locations(item.alertId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Live location timeline', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ViraColors.plum)),
                const SizedBox(height: 6),
                Text('${points.length} location update${points.length == 1 ? '' : 's'} stored for this emergency.', style: const TextStyle(color: ViraColors.mutedPlum)),
                const SizedBox(height: 14),
                if (points.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: ViraColors.lilac, borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Latest: ${points.last.latitude.toStringAsFixed(5)}, ${points.last.longitude.toStringAsFixed(5)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(DateFormat('dd MMM, h:mm:ss a').format(points.last.recordedAt.toLocal()), style: const TextStyle(color: ViraColors.mutedPlum)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Color _cardColor(InboxAlert item) {
    if (item.state == 'cancelled') return ViraColors.lilac;
    if (item.state == 'resolved') return ViraColors.successSoft;
    return item.acknowledgedAt != null ? ViraColors.successSoft : ViraColors.dangerSoft;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
        children: [
          Row(
            children: [
              Expanded(child: Text('Emergency Inbox', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: ViraColors.plum))),
              const _LiveBadge(),
            ],
          ),
          const SizedBox(height: 6),
          const Text('Auto-refreshes every 5 seconds while the app is running. Opening the inbox counts as server-confirmed delivery.', style: TextStyle(color: ViraColors.mutedPlum, height: 1.35)),
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
                  decoration: BoxDecoration(color: _cardColor(item), borderRadius: BorderRadius.circular(22)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            item.state == 'resolved'
                                ? Icons.health_and_safety
                                : item.state == 'cancelled'
                                    ? Icons.cancel_outlined
                                    : item.acknowledgedAt != null
                                        ? Icons.check_circle
                                        : Icons.crisis_alert_rounded,
                            color: item.state == 'resolved' || item.acknowledgedAt != null ? ViraColors.success : item.state == 'cancelled' ? ViraColors.mutedPlum : ViraColors.pinkDark,
                          ),
                          const SizedBox(width: 9),
                          Expanded(child: Text('${item.senderName} ${item.isTest ? 'sent a TEST DRILL' : item.isActive ? 'needs help' : item.state == 'resolved' ? 'is marked safe' : 'cancelled the alert'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                          if (item.isTest) const _TestBadge(),
                          if (item.isActive) const SizedBox(width: 6),
                          if (item.isActive) _LiveBadge.fromAlert(item),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Started ${DateFormat('dd MMM, h:mm a').format(item.createdAt.toLocal())}', style: const TextStyle(color: ViraColors.mutedPlum)),
                      Text('Last location ${DateFormat('h:mm:ss a').format(item.updatedAt.toLocal())}', style: const TextStyle(color: ViraColors.mutedPlum, fontSize: 12)),
                      const SizedBox(height: 7),
                      SelectableText('GPS: ${item.latitude.toStringAsFixed(5)}, ${item.longitude.toStringAsFixed(5)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 12,
                        children: [
                          if (item.batteryPercent != null) Text('Battery ${item.batteryPercent}%', style: const TextStyle(color: ViraColors.mutedPlum)),
                          if (item.networkState != null) Text(item.networkState!.toUpperCase(), style: const TextStyle(color: ViraColors.mutedPlum)),
                        ],
                      ),
                      if (item.note != null) ...[
                        const SizedBox(height: 5),
                        Text(item.note!),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: FilledButton.tonalIcon(onPressed: () => _openMap(item), icon: const Icon(Icons.map_outlined), label: const Text('Open map'))),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(onPressed: () => _showTimeline(item), icon: const Icon(Icons.route_outlined), tooltip: 'Location timeline'),
                        ],
                      ),
                      if (item.isActive) ...[
                        const SizedBox(height: 8),
                        if (item.acknowledgedAt == null)
                          FilledButton.icon(onPressed: () => _ack(item), icon: const Icon(Icons.volunteer_activism), label: const Text("I'm responding — acknowledge"))
                        else
                          const Text('Acknowledged — sender can see that you received this.', style: TextStyle(color: ViraColors.success, fontWeight: FontWeight.w900)),
                      ],
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

class _TestBadge extends StatelessWidget {
  const _TestBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: ViraColors.gold, borderRadius: BorderRadius.circular(99)),
      child: const Text('TEST', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8)),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({this.alert});
  const _LiveBadge.fromAlert(InboxAlert this.alert);

  final InboxAlert? alert;

  String get label {
    final item = alert;
    if (item == null) return 'LIVE';
    final seen = item.lastDeviceSeenAt ?? item.updatedAt;
    final age = DateTime.now().difference(seen.toLocal());
    if (age < const Duration(seconds: 20)) return 'LIVE';
    if (age < const Duration(minutes: 2)) return 'DELAYED';
    return 'LAST SEEN';
  }

  Color get color {
    switch (label) {
      case 'LIVE':
        return ViraColors.success;
      case 'DELAYED':
        return ViraColors.warning;
      default:
        return ViraColors.mutedPlum;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8)),
    );
  }
}
