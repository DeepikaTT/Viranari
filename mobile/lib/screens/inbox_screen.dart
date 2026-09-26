import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import 'live_tracking_screen.dart';

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
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _load(silent: true));
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
        await (newest.isTest ? HapticFeedback.selectionClick() : HapticFeedback.heavyImpact());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(newest.isTest
                ? 'TEST DRILL from ${newest.senderName}.'
                : newest.silentMode
                    ? 'Silent SOS from ${newest.senderName}. They may be unable to interact safely.'
                    : 'Emergency: ${newest.senderName} needs help. Open Live Track.'),
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
        const SnackBar(content: Text('Acknowledgement sent. Do not confront danger alone; bring help or contact emergency services.')),
      );
    }
  }

  Future<void> _openExternalMap(InboxAlert item) async {
    final uri = Uri.parse('geo:${item.latitude},${item.longitude}?q=${item.latitude},${item.longitude}(ViraNari%20SOS)');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No map app could open this location.')));
    }
  }

  Future<void> _call(InboxAlert item) async {
    final phone = item.senderPhoneE164;
    if (phone == null) return;
    await launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication);
  }

  Future<void> _track(InboxAlert item) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LiveTrackingScreen(session: widget.session, initial: item),
    ));
    await _load();
  }

  Duration _age(InboxAlert item) {
    final source = item.lastDeviceSeenAt ?? item.updatedAt;
    final d = DateTime.now().difference(source.toLocal());
    return d.isNegative ? Duration.zero : d;
  }

  String _freshness(InboxAlert item) {
    final age = _age(item);
    if (!item.isActive) return item.state.toUpperCase();
    if (age.inSeconds < 15) return 'LIVE';
    if (age.inMinutes < 2) return 'DELAYED';
    return 'LAST SEEN';
  }

  Color _freshnessColor(InboxAlert item) {
    final age = _age(item);
    if (!item.isActive) return ViraColors.mutedPlum;
    if (age.inSeconds < 15) return ViraColors.success;
    if (age.inMinutes < 2) return ViraColors.warning;
    return ViraColors.pinkDark;
  }

  String _ageText(InboxAlert item) {
    final age = _age(item);
    if (age.inSeconds < 10) return 'just now';
    if (age.inSeconds < 60) return '${age.inSeconds}s ago';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    return '${age.inHours}h ago';
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
          Row(children: [
            Expanded(child: Text('Emergency Inbox', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: ViraColors.plum))),
            const _LiveBadge(),
          ]),
          const SizedBox(height: 6),
          const Text('Refreshes every 3 seconds while open. “Last seen” means the device stopped updating; the marker remains at the last reliable point.', style: TextStyle(color: ViraColors.mutedPlum, height: 1.35)),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: ViraColors.pinkDark))
          else if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: ViraColors.lilac, borderRadius: BorderRadius.circular(24)),
              child: const Column(children: [
                Icon(Icons.inbox_outlined, size: 44, color: ViraColors.plum),
                SizedBox(height: 10),
                Text('No emergency alerts', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              ]),
            )
          else
            ..._items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(color: _cardColor(item), borderRadius: BorderRadius.circular(22)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
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
                        Expanded(
                          child: Text(
                            '${item.senderName} ${item.isTest ? 'sent a TEST DRILL' : item.silentMode && item.isActive ? 'started a SILENT SOS' : item.isActive ? 'needs help' : item.state == 'resolved' ? 'is marked safe' : 'cancelled the alert'}',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                          ),
                        ),
                        if (item.isTest) const _TestBadge(),
                        if (item.silentMode && !item.isTest) const _SilentBadge(),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(color: _freshnessColor(item), borderRadius: BorderRadius.circular(99)),
                          child: Text(_freshness(item), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                        ),
                        const SizedBox(width: 8),
                        Text('${_ageText(item)} · ${DateFormat('h:mm:ss a').format((item.lastDeviceSeenAt ?? item.updatedAt).toLocal())}', style: const TextStyle(color: ViraColors.mutedPlum, fontSize: 12)),
                      ]),
                      const SizedBox(height: 7),
                      SelectableText('GPS: ${item.latitude.toStringAsFixed(5)}, ${item.longitude.toStringAsFixed(5)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      Wrap(spacing: 12, runSpacing: 5, children: [
                        if (item.batteryPercent != null) Text('Battery ${item.batteryPercent}%', style: const TextStyle(color: ViraColors.mutedPlum)),
                        if (item.networkState != null) Text(item.networkState!.toUpperCase(), style: const TextStyle(color: ViraColors.mutedPlum)),
                        Text('Started ${DateFormat('dd MMM, h:mm a').format(item.createdAt.toLocal())}', style: const TextStyle(color: ViraColors.mutedPlum)),
                      ]),
                      if (item.silentMode && item.isActive) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Silent SOS: the sender may be unable to speak, type, or visibly use the app.',
                          style: TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w900),
                        ),
                      ],
                      if (item.isActive && _age(item).inMinutes >= 2) ...[
                        const SizedBox(height: 8),
                        const Text('⚠ Device connection appears lost. Use this as the last known location.', style: TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w900)),
                      ],
                      if (item.note != null) ...[
                        const SizedBox(height: 5),
                        Text(item.note!),
                      ],
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: FilledButton.icon(onPressed: () => _track(item), icon: const Icon(Icons.my_location), label: const Text('Live Track'))),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(onPressed: () => _openExternalMap(item), icon: const Icon(Icons.map_outlined), tooltip: 'Open external map'),
                        if (item.senderPhoneE164 != null) ...[
                          const SizedBox(width: 4),
                          IconButton.filledTonal(onPressed: () => _call(item), icon: const Icon(Icons.call), tooltip: 'Call sender'),
                        ],
                      ]),
                      if (item.isActive) ...[
                        const SizedBox(height: 8),
                        if (item.acknowledgedAt == null)
                          FilledButton.tonalIcon(onPressed: () => _ack(item), icon: const Icon(Icons.volunteer_activism), label: const Text("I'm responding — acknowledge"))
                        else
                          const Text('Acknowledged — sender can see that you received this.', style: TextStyle(color: ViraColors.success, fontWeight: FontWeight.w900)),
                      ],
                    ]),
                  ),
                )),
        ],
      ),
    );
  }
}

class _TestBadge extends StatelessWidget {
  const _TestBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(color: ViraColors.gold, borderRadius: BorderRadius.circular(99)),
        child: const Text('TEST', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8)),
      );
}

class _SilentBadge extends StatelessWidget {
  const _SilentBadge();
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: ViraColors.pinkDark, borderRadius: BorderRadius.circular(99)),
        child: const Text(
          'SILENT',
          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .7),
        ),
      );
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: ViraColors.pinkDark, borderRadius: BorderRadius.circular(99)),
        child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8)),
      );
}
