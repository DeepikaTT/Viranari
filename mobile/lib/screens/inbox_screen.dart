import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import 'safe_reach_sheet.dart';

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

  Future<void> _callSender(InboxAlert item) async {
    final phone = item.senderPhoneE164;
    if (phone == null || phone.isEmpty) return;
    final opened = await launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the phone app.')));
    }
  }

  Future<void> _showSafeReach(InboxAlert item) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: ViraColors.surface,
      showDragHandle: true,
      builder: (_) => SafeReachSheet(session: widget.session, alertId: item.alertId),
    );
    await _load(silent: true);
  }

  Future<void> _showTimeline(InboxAlert item) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: ViraColors.surface,
      showDragHandle: true,
      builder: (_) => _LocationTimelineSheet(
        session: widget.session,
        alert: item,
      ),
    );
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
                          if (item.senderPhoneE164 != null) ...[
                            const SizedBox(width: 8),
                            IconButton.filled(onPressed: () => _callSender(item), icon: const Icon(Icons.call_rounded), tooltip: 'Call sender'),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showSafeReach(item),
                          icon: Icon(item.safeReach == null ? Icons.verified_user_outlined : Icons.verified_user_rounded),
                          label: Text(
                            item.safeReach == null
                                ? 'SafeReach · verified emergency help'
                                : 'SafeReach · ${item.safeReach!.statusLabel}',
                          ),
                        ),
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


class _LocationTimelineSheet extends StatefulWidget {
  const _LocationTimelineSheet({required this.session, required this.alert});

  final AppSession session;
  final InboxAlert alert;

  @override
  State<_LocationTimelineSheet> createState() => _LocationTimelineSheetState();
}

class _LocationTimelineSheetState extends State<_LocationTimelineSheet> {
  List<AlertLocationPoint> _points = const [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await widget.session.api.locations(widget.alert.alertId);
      final ordered = [...data]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      if (!mounted) return;
      setState(() {
        _points = ordered;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _openPoint(AlertLocationPoint point) async {
    final uri = Uri.parse(
      'geo:${point.latitude},${point.longitude}?q=${point.latitude},${point.longitude}(ViraNari%20location)',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No map app could open this location.')),
      );
    }
  }

  String _time(AlertLocationPoint point) =>
      DateFormat('dd MMM, h:mm:ss a').format(point.recordedAt.toLocal());

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .82,
      minChildSize: .45,
      maxChildSize: .96,
      builder: (context, scrollController) {
        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Live location timeline',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: ViraColors.plum,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: widget.alert.isActive ? ViraColors.success : ViraColors.mutedPlum,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              widget.alert.isActive ? 'LIVE' : widget.alert.state.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .7,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_points.length} location update${_points.length == 1 ? '' : 's'} stored • newest first • refreshes every 5 seconds',
                        style: const TextStyle(color: ViraColors.mutedPlum, height: 1.35),
                      ),
                      if (_points.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: ViraColors.lilac,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'LATEST FIX',
                                style: TextStyle(
                                  color: ViraColors.plum,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .8,
                                ),
                              ),
                              const SizedBox(height: 5),
                              SelectableText(
                                '${_points.first.latitude.toStringAsFixed(5)}, ${_points.first.longitude.toStringAsFixed(5)}',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _time(_points.first),
                                style: const TextStyle(color: ViraColors.mutedPlum),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w700),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              if (_loading && _points.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_points.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'No location records have reached the server yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: ViraColors.mutedPlum),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final point = _points[index];
                        final sequence = _points.length - index;
                        return _TimelineRecord(
                          point: point,
                          sequence: sequence,
                          isLatest: index == 0,
                          isLast: index == _points.length - 1,
                          onOpenMap: () => _openPoint(point),
                        );
                      },
                      childCount: _points.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineRecord extends StatelessWidget {
  const _TimelineRecord({
    required this.point,
    required this.sequence,
    required this.isLatest,
    required this.isLast,
    required this.onOpenMap,
  });

  final AlertLocationPoint point;
  final int sequence;
  final bool isLatest;
  final bool isLast;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    final local = point.recordedAt.toLocal();
    final meta = <String>[
      if (point.accuracyM != null) '±${point.accuracyM!.toStringAsFixed(0)} m',
      if (point.batteryPercent != null) 'Battery ${point.batteryPercent}%',
      if (point.networkState != null) point.networkState!.toUpperCase(),
      if (point.speedMps != null && point.speedMps! >= 0.5)
        '${(point.speedMps! * 3.6).toStringAsFixed(1)} km/h',
    ];

    return Stack(
      children: [
        if (!isLast)
          Positioned(
            left: 6,
            top: 14,
            bottom: 0,
            child: Container(width: 2, color: ViraColors.lilacStrong),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Container(
                width: isLatest ? 14 : 12,
                height: isLatest ? 14 : 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isLatest ? ViraColors.success : ViraColors.plum,
                  border: Border.all(color: ViraColors.surface, width: 2),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  decoration: BoxDecoration(
                    color: isLatest ? ViraColors.successSoft : ViraColors.lilac,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isLatest ? 'Latest location' : 'Location #$sequence',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          Text(
                            DateFormat('h:mm:ss a').format(local),
                            style: const TextStyle(
                              color: ViraColors.mutedPlum,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      SelectableText(
                        '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        DateFormat('dd MMM yyyy').format(local),
                        style: const TextStyle(color: ViraColors.mutedPlum, fontSize: 12),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 8,
                          runSpacing: 5,
                          children: meta
                              .map(
                                (value) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: ViraColors.surface,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    value,
                                    style: const TextStyle(
                                      color: ViraColors.mutedPlum,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: onOpenMap,
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: const Text('Open this point'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
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
