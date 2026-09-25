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

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  final MapController _mapController = MapController();
  Timer? _timer;
  AlertRecord? _alert;
  List<AlertLocationPoint> _points = const [];
  bool _loading = true;
  String? _error;
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
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
          if (mounted) _mapController.move(LatLng(last.latitude, last.longitude), 16.5);
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => _error = e.toString());
      setState(() => _loading = false);
    }
  }

  Duration get _age {
    final time = _points.isNotEmpty ? _points.last.recordedAt : (_alert?.updatedAt ?? widget.initial.updatedAt);
    final d = DateTime.now().difference(time.toLocal());
    return d.isNegative ? Duration.zero : d;
  }

  String get _freshnessLabel {
    if (_age.inSeconds < 15) return 'LIVE';
    if (_age.inMinutes < 2) return 'DELAYED';
    return 'LAST SEEN';
  }

  Color get _freshnessColor {
    if (_age.inSeconds < 15) return ViraColors.success;
    if (_age.inMinutes < 2) return ViraColors.warning;
    return ViraColors.pinkDark;
  }

  String get _ageText {
    if (_age.inSeconds < 10) return 'just now';
    if (_age.inSeconds < 60) return '${_age.inSeconds}s ago';
    if (_age.inMinutes < 60) return '${_age.inMinutes}m ago';
    return '${_age.inHours}h ago';
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
    if (deg == null) return 'Unknown';
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return dirs[((deg + 22.5) ~/ 45) % 8];
  }

  Future<void> _acknowledge() async {
    await widget.session.api.acknowledge(widget.initial.alertId);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Acknowledgement sent to the person in danger.')));
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
            recordedAt: widget.initial.updatedAt,
            accuracyM: widget.initial.accuracyM,
            batteryPercent: widget.initial.batteryPercent,
            networkState: widget.initial.networkState,
          );
    final latLng = LatLng(latest.latitude, latest.longitude);
    final bearing = latest.headingDeg ?? _bearingDeg();
    final speed = latest.speedMps;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.initial.senderName} · Live Safety'),
        actions: [
          IconButton(
            tooltip: _follow ? 'Stop following marker' : 'Follow marker',
            onPressed: () => setState(() => _follow = !_follow),
            icon: Icon(_follow ? Icons.gps_fixed : Icons.gps_not_fixed),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  color: ViraColors.surface,
                  child: Column(children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: _freshnessColor, borderRadius: BorderRadius.circular(99)),
                        child: Text(_freshnessLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Updated $_ageText · ${DateFormat('h:mm:ss a').format(latest.recordedAt.toLocal())}', style: const TextStyle(fontWeight: FontWeight.w800))),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 14, runSpacing: 8, children: [
                      Text('Accuracy ±${latest.accuracyM?.toStringAsFixed(0) ?? '--'} m'),
                      Text('Battery ${latest.batteryPercent ?? '--'}%'),
                      Text((latest.networkState ?? 'unknown').toUpperCase()),
                      Text('Direction ${_direction(bearing)}'),
                      if (speed != null) Text('${(speed * 3.6).toStringAsFixed(1)} km/h'),
                    ]),
                    if (_age.inMinutes >= 2) ...[
                      const SizedBox(height: 8),
                      const Row(children: [
                        Icon(Icons.warning_amber_rounded, color: ViraColors.pinkDark),
                        SizedBox(width: 7),
                        Expanded(child: Text('Device updates stopped. Treat this as the last known location, not a live position.', style: TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w800))),
                      ]),
                    ],
                  ]),
                ),
                Expanded(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(initialCenter: latLng, initialZoom: 16.5),
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
                      MarkerLayer(markers: [
                        Marker(
                          point: latLng,
                          width: 64,
                          height: 64,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _freshnessColor.withValues(alpha: .18),
                            ),
                            child: Center(
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: _freshnessColor, border: Border.all(color: Colors.white, width: 4)),
                              ),
                            ),
                          ),
                        ),
                      ]),
                      RichAttributionWidget(
                        attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: ViraColors.pinkDark))),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      if (widget.initial.senderPhoneE164 != null) ...[
                        Expanded(child: FilledButton.tonalIcon(onPressed: _call, icon: const Icon(Icons.call), label: const Text('Call'))),
                        const SizedBox(width: 8),
                      ],
                      Expanded(child: FilledButton.icon(onPressed: _acknowledge, icon: const Icon(Icons.volunteer_activism), label: const Text("I'm responding"))),
                    ]),
                  ),
                ),
              ],
            ),
    );
  }
}
