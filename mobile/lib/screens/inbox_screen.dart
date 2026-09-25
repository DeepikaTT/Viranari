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
  bool _polling = false;
  bool _firstLoad = true;
  String? _error;
  Timer? _pollTimer;
  Set<String> _knownIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_polling) return;
    _polling = true;
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
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
          SnackBar(content: Text(newest.isTest ? 'TEST DRILL from ${newest.senderName}.' : 'Emergency: ${newest.senderName} needs help.')),
        );
      }
      _firstLoad = false;
    } on ApiException catch (e) {
      if (mounted && !silent) setState(() => _error = e.message);
    } finally {
      _polling = false;
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Duration _age(DateTime? time) {
    if (time == null) return const Duration(days: 365);
    final d = DateTime.now().difference(time.toLocal());
    return d.isNegative ? Duration.zero : d;
  }

  String _deviceState(InboxAlert item) {
    if (!item.isActive) return item.state.toUpperCase();
    final age = _age(item.lastDeviceSeenAt ?? item.updatedAt);
    if (age.inSeconds < 20) return 'LIVE';
    if (age.inSeconds < 60) return 'DELAYED';
    return 'OFFLINE';
  }

  Color _deviceColor(InboxAlert item) {
    switch (_deviceState(item)) {
      case 'LIVE': return ViraColors.success;
      case 'DELAYED': return ViraColors.warning;
      case 'OFFLINE': return ViraColors.pinkDark;
      default: return ViraColors.mutedPlum;
    }
  }

  String _ageText(DateTime? time) {
    final age = _age(time);
    if (age.inSeconds < 10) return 'just now';
    if (age.inSeconds < 60) return '${age.inSeconds}s ago';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    return '${age.inHours}h ago';
  }

  Future<void> _ack(InboxAlert item) async {
    await widget.session.api.acknowledge(item.alertId);
    await HapticFeedback.mediumImpact();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The sender can now see that you are responding.')));
    }
  }

  Future<void> _map(InboxAlert item) async {
    final uri = Uri.parse('geo:${item.latitude},${item.longitude}?q=${item.latitude},${item.longitude}(ViraNari%20SOS)');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _call(String? phone) async {
    if (phone == null) return;
    await launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication);
  }

  Future<void> _track(InboxAlert item) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LiveTrackingScreen(session: widget.session, initial: item)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
        children: [
          Text('Response', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: ViraColors.plum)),
          const SizedBox(height: 4),
          const Text('Emergency alerts from people who trust you.', style: TextStyle(color: ViraColors.mutedPlum)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Text('Emergency alerts', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(color: ViraColors.successSoft, borderRadius: BorderRadius.circular(99)),
                child: const Text('AUTO REFRESH', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: ViraColors.success)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_loading)
            const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(_error!, style: const TextStyle(color: ViraColors.pinkDark)))
          else if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Column(children: [
                Icon(Icons.shield_outlined, size: 42, color: ViraColors.mutedPlum),
                SizedBox(height: 10),
                Text('No emergency alerts', style: TextStyle(fontWeight: FontWeight.w900)),
              ]),
            )
          else
            ..._items.map((item) => _EmergencyRow(
                  item: item,
                  state: _deviceState(item),
                  stateColor: _deviceColor(item),
                  deviceSeenText: _ageText(item.lastDeviceSeenAt ?? item.updatedAt),
                  gpsSeenText: _ageText(item.lastGpsFixAt ?? item.updatedAt),
                  onTrack: () => _track(item),
                  onMap: () => _map(item),
                  onCall: item.senderPhoneE164 == null ? null : () => _call(item.senderPhoneE164),
                  onAck: item.isActive && item.acknowledgedAt == null ? () => _ack(item) : null,
                )),
        ],
      ),
    );
  }
}

class _EmergencyRow extends StatelessWidget {
  const _EmergencyRow({
    required this.item,
    required this.state,
    required this.stateColor,
    required this.deviceSeenText,
    required this.gpsSeenText,
    required this.onTrack,
    required this.onMap,
    this.onCall,
    this.onAck,
  });

  final InboxAlert item;
  final String state;
  final Color stateColor;
  final String deviceSeenText;
  final String gpsSeenText;
  final VoidCallback onTrack;
  final VoidCallback onMap;
  final VoidCallback? onCall;
  final VoidCallback? onAck;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: ViraColors.lilacStrong))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: stateColor)),
                const SizedBox(width: 9),
                Expanded(child: Text(item.senderName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                Text(state, style: TextStyle(fontWeight: FontWeight.w900, color: stateColor, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              item.isActive ? 'Phone $deviceSeenText · GPS $gpsSeenText' : '${item.state.toUpperCase()} · ${DateFormat('dd MMM, h:mm a').format(item.updatedAt.toLocal())}',
              style: const TextStyle(color: ViraColors.mutedPlum),
            ),
            if (item.isActive && state == 'OFFLINE') ...[
              const SizedBox(height: 5),
              const Text('Connection lost — last known location retained.', style: TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w800)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(onPressed: onTrack, icon: const Icon(Icons.my_location_rounded), label: const Text('Track')),
                const SizedBox(width: 7),
                IconButton.filledTonal(onPressed: onMap, icon: const Icon(Icons.map_outlined), tooltip: 'Open map'),
                if (onCall != null) ...[
                  const SizedBox(width: 4),
                  IconButton.filledTonal(onPressed: onCall, icon: const Icon(Icons.call_rounded), tooltip: 'Call'),
                ],
                const Spacer(),
                if (onAck != null) TextButton(onPressed: onAck, child: const Text("I'm responding")),
              ],
            ),
          ],
        ),
      );
}

