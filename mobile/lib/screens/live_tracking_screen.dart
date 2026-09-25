import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';

class LiveTrackingScreen extends StatefulWidget {
  const LiveTrackingScreen({super.key, required this.session, required this.initial});
  final AppSession session;
  final InboxAlert initial;

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  Timer? _timer;
  AlertRecord? _alert;
  List<AlertLocationPoint> _points = const [];
  bool _loading = true;
  bool _refreshing = false;
  bool _follow = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh(silent: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final results = await Future.wait([
        widget.session.api.getAlert(widget.initial.alertId),
        widget.session.api.locations(widget.initial.alertId),
      ]);
      final alert = results[0] as AlertRecord;
      final points = results[1] as List<AlertLocationPoint>;
      if (!mounted) return;
      setState(() {
        _alert = alert;
        _points = points;
        _error = null;
        _loading = false;
      });
      if (_follow && points.isNotEmpty) {
        final last = points.last;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _mapController.move(LatLng(last.latitude, last.longitude), 16.7);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.toString();
      });
    } finally {
      _refreshing = false;
    }
  }

  Duration _age(DateTime? time) {
    if (time == null) return const Duration(days: 365);
    final value = DateTime.now().difference(time.toLocal());
    return value.isNegative ? Duration.zero : value;
  }

  DateTime? get _deviceSeen => _alert?.lastDeviceSeenAt ?? widget.initial.lastDeviceSeenAt ?? _alert?.updatedAt ?? widget.initial.updatedAt;
  DateTime? get _gpsFix => _alert?.lastGpsFixAt ?? widget.initial.lastGpsFixAt ?? (_points.isNotEmpty ? _points.last.recordedAt : null);

  String get _deviceState {
    final alert = _alert;
    if (alert != null && !alert.isActive) return alert.state.toUpperCase();
    final age = _age(_deviceSeen);
    if (age.inSeconds < 20) return 'LIVE';
    if (age.inSeconds < 60) return 'DELAYED';
    return 'OFFLINE';
  }

  Color get _deviceColor {
    switch (_deviceState) {
      case 'LIVE':
        return ViraColors.success;
      case 'DELAYED':
        return ViraColors.warning;
      case 'OFFLINE':
        return ViraColors.pinkDark;
      default:
        return ViraColors.mutedPlum;
    }
  }

  String _ageText(DateTime? time) {
    final age = _age(time);
    if (age.inSeconds < 10) return 'just now';
    if (age.inSeconds < 60) return '${age.inSeconds}s ago';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    return '${age.inHours}h ago';
  }

  double? _bearingDeg() {
    if (_points.length < 2) return null;
    final a = _points[_points.length - 2];
    final b = _points.last;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  String _direction(double? deg) {
    if (deg == null) return '—';
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return dirs[((deg + 22.5) ~/ 45) % 8];
  }

  double _distanceMeters(AlertLocationPoint a, AlertLocationPoint b) {
    const r = 6371000.0;
    final p1 = a.latitude * math.pi / 180;
    final p2 = b.latitude * math.pi / 180;
    final dp = (b.latitude - a.latitude) * math.pi / 180;
    final dl = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * r * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double get _distanceTravelled {
    var total = 0.0;
    for (var i = 1; i < _points.length; i++) {
      final segment = _distanceMeters(_points[i - 1], _points[i]);
      // Reject impossible GPS jumps in the prototype trail.
      if (segment < 2000) total += segment;
    }
    return total;
  }

  String _formatDistance(double metres) => metres >= 1000 ? '${(metres / 1000).toStringAsFixed(2)} km' : '${metres.toStringAsFixed(0)} m';

  Future<void> _acknowledge() async {
    await widget.session.api.acknowledge(widget.initial.alertId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The sender can now see that you are responding.')));
    }
  }

  Future<void> _call() async {
    final phone = widget.initial.senderPhoneE164;
    if (phone == null) return;
    await launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final latest = _points.isNotEmpty
        ? _points.last
        : AlertLocationPoint(
            latitude: widget.initial.latitude,
            longitude: widget.initial.longitude,
            recordedAt: widget.initial.lastGpsFixAt ?? widget.initial.updatedAt,
            accuracyM: widget.initial.accuracyM,
            batteryPercent: widget.initial.batteryPercent,
            networkState: widget.initial.networkState,
          );
    final center = LatLng(latest.latitude, latest.longitude);
    final bearing = latest.headingDeg ?? _bearingDeg();
    final locationAge = _age(_gpsFix ?? latest.recordedAt);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.initial.senderName} · Live Safety'),
        actions: [
          IconButton(
            tooltip: _follow ? 'Stop following marker' : 'Follow marker',
            onPressed: () => setState(() => _follow = !_follow),
            icon: Icon(_follow ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(initialCenter: center, initialZoom: 16.7),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.viranari.viranari_app',
                      ),
                      if (_points.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
                              strokeWidth: 5,
                              color: ViraColors.pink,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: center,
                            width: 68,
                            height: 68,
                            child: Container(
                              decoration: BoxDecoration(shape: BoxShape.circle, color: _deviceColor.withValues(alpha: .16)),
                              child: Center(
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _deviceColor,
                                    border: Border.all(color: Colors.white, width: 4),
                                    boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
                    ],
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  top: 12,
                  child: _GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: _deviceColor, borderRadius: BorderRadius.circular(99)),
                              child: Text(_deviceState, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Phone seen ${_ageText(_deviceSeen)}',
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          locationAge.inSeconds < 30
                              ? 'Location ${_ageText(_gpsFix ?? latest.recordedAt)} · ${DateFormat('h:mm:ss a').format(latest.recordedAt.toLocal())}'
                              : 'Phone is ${_deviceState == 'LIVE' ? 'online' : _deviceState.toLowerCase()}, but the last GPS fix is ${_ageText(_gpsFix ?? latest.recordedAt)}.',
                          style: TextStyle(color: locationAge.inSeconds < 30 ? ViraColors.mutedPlum : ViraColors.warning, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: SafeArea(
                    top: false,
                    child: _GlassPanel(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(child: _MiniMetric(label: 'Battery', value: '${latest.batteryPercent ?? '--'}%')),
                              Expanded(child: _MiniMetric(label: 'Direction', value: _direction(bearing))),
                              Expanded(child: _MiniMetric(label: 'Trail', value: _formatDistance(_distanceTravelled))),
                              Expanded(child: _MiniMetric(label: 'Accuracy', value: latest.accuracyM == null ? '—' : '±${latest.accuracyM!.toStringAsFixed(0)}m')),
                            ],
                          ),
                          if (_deviceState == 'OFFLINE') ...[
                            const SizedBox(height: 10),
                            const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: ViraColors.pinkDark),
                                SizedBox(width: 7),
                                Expanded(child: Text('Connection lost. The marker is the last reliable location.', style: TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w800))),
                              ],
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(_error!, style: const TextStyle(color: ViraColors.pinkDark)),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              if (widget.initial.senderPhoneE164 != null) ...[
                                Expanded(child: FilledButton.tonalIcon(onPressed: _call, icon: const Icon(Icons.call_rounded), label: const Text('Call'))),
                                const SizedBox(width: 8),
                              ],
                              Expanded(child: FilledButton.icon(onPressed: _acknowledge, icon: const Icon(Icons.volunteer_activism_rounded), label: const Text("I'm responding"))),
                            ],
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

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        elevation: 3,
        color: ViraColors.surface.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(20),
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      );
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: ViraColors.plum)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: ViraColors.mutedPlum)),
        ],
      );
}
