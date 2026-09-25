import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../services/location_service.dart';

class LiveMapHubScreen extends StatefulWidget {
  const LiveMapHubScreen({super.key, required this.session});
  final AppSession session;

  @override
  State<LiveMapHubScreen> createState() => _LiveMapHubScreenState();
}

class _LiveMapHubScreenState extends State<LiveMapHubScreen> with WidgetsBindingObserver {
  final _mapController = MapController();
  final _location = LocationService();
  Timer? _timer;
  AlertRecord? _alert;
  InboxAlert? _inboxAlert;
  List<AlertLocationPoint> _points = const [];
  PositionSnapshot? _idlePosition;
  bool _loading = true;
  bool _refreshing = false;
  bool _follow = true;
  bool _ownEmergency = false;
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
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
    try {
      AlertRecord? active;
      InboxAlert? inbox;
      var own = false;

      try {
        active = await widget.session.api.activeAlert();
        own = active != null;
      } catch (_) {}

      if (active == null) {
        final inboxItems = await widget.session.api.inbox();
        final activeItems = inboxItems.where((e) => e.isActive).toList();
        if (activeItems.isNotEmpty) {
          inbox = activeItems.first;
          active = await widget.session.api.getAlert(inbox.alertId);
        }
      }

      List<AlertLocationPoint> points = const [];
      PositionSnapshot? idle;
      if (active != null) {
        points = await widget.session.api.locations(active.id);
      } else {
        try {
          final p = await _location.current();
          idle = PositionSnapshot(latitude: p.latitude, longitude: p.longitude, accuracyM: p.accuracy);
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _alert = active;
        _inboxAlert = inbox;
        _points = points;
        _idlePosition = idle;
        _ownEmergency = own;
        _loading = false;
        _error = null;
      });

      final center = _currentCenter;
      if (_follow && center != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _mapController.move(center, active == null ? 15.5 : 16.8);
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() { _loading = false; _error = e.toString(); });
    } finally {
      _refreshing = false;
    }
  }

  LatLng? get _currentCenter {
    if (_points.isNotEmpty) {
      final p = _points.last;
      return LatLng(p.latitude, p.longitude);
    }
    if (_alert != null) return LatLng(_alert!.latitude, _alert!.longitude);
    if (_idlePosition != null) return LatLng(_idlePosition!.latitude, _idlePosition!.longitude);
    return null;
  }

  Duration _age(DateTime? t) {
    if (t == null) return const Duration(days: 365);
    final d = DateTime.now().difference(t.toLocal());
    return d.isNegative ? Duration.zero : d;
  }

  String get _state {
    final a = _alert;
    if (a == null || !a.isActive) return 'READY';
    final age = _age(a.lastDeviceSeenAt ?? a.updatedAt);
    if (age.inSeconds < 20) return 'LIVE';
    if (age.inSeconds < 60) return 'DELAYED';
    return 'OFFLINE';
  }

  Color get _stateColor {
    switch (_state) {
      case 'LIVE': return ViraColors.success;
      case 'DELAYED': return ViraColors.warning;
      case 'OFFLINE': return ViraColors.pinkDark;
      default: return ViraColors.plum;
    }
  }

  double _distance(AlertLocationPoint a, AlertLocationPoint b) {
    const r = 6371000.0;
    final p1 = a.latitude * math.pi / 180;
    final p2 = b.latitude * math.pi / 180;
    final dp = (b.latitude - a.latitude) * math.pi / 180;
    final dl = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * r * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double get _trailDistance {
    var total = 0.0;
    for (var i = 1; i < _points.length; i++) {
      final d = _distance(_points[i - 1], _points[i]);
      if (d < 2000) total += d;
    }
    return total;
  }

  String _distanceText(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(2)} km' : '${m.toStringAsFixed(0)} m';

  String _ageText(DateTime? t) {
    final age = _age(t);
    if (age.inSeconds < 10) return 'just now';
    if (age.inSeconds < 60) return '${age.inSeconds}s ago';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    return '${age.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final center = _currentCenter;
    final latest = _points.isNotEmpty ? _points.last : null;
    final title = _ownEmergency
        ? 'Your live emergency'
        : _inboxAlert != null
            ? '${_inboxAlert!.senderName} · Live Map'
            : 'Live Map';

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : center == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_off_outlined, size: 44, color: ViraColors.mutedPlum),
                        const SizedBox(height: 12),
                        const Text('Map is ready, but no location is available yet.', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _refresh, child: const Text('Try again')),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(initialCenter: center, initialZoom: _alert == null ? 15.5 : 16.8),
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
                                width: 72,
                                height: 72,
                                child: Container(
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: _stateColor.withValues(alpha: .16)),
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 25,
                                    height: 25,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _stateColor,
                                      border: Border.all(color: Colors.white, width: 4),
                                      boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
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
                      child: SafeArea(
                        bottom: false,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .93),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [BoxShadow(blurRadius: 16, color: Colors.black12)],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                    const SizedBox(height: 3),
                                    Text(
                                      _alert == null
                                          ? 'No active emergency · showing this phone'
                                          : 'Phone ${_ageText(_alert!.lastDeviceSeenAt ?? _alert!.updatedAt)} · GPS ${_ageText(_alert!.lastGpsFixAt ?? latest?.recordedAt)}',
                                      style: const TextStyle(color: ViraColors.mutedPlum, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: _stateColor, borderRadius: BorderRadius.circular(99)),
                                child: Text(_state, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                onPressed: () => setState(() => _follow = !_follow),
                                icon: Icon(_follow ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded),
                                tooltip: _follow ? 'Following marker' : 'Follow marker',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 14,
                      child: SafeArea(
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .94),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [BoxShadow(blurRadius: 16, color: Colors.black12)],
                          ),
                          child: Row(
                            children: [
                              Expanded(child: _Metric(label: 'Trail', value: _distanceText(_trailDistance))),
                              Expanded(child: _Metric(label: 'Accuracy', value: latest?.accuracyM == null ? (_idlePosition?.accuracyM == null ? '—' : '±${_idlePosition!.accuracyM!.toStringAsFixed(0)}m') : '±${latest!.accuracyM!.toStringAsFixed(0)}m')),
                              Expanded(child: _Metric(label: 'Battery', value: latest?.batteryPercent == null ? '${_alert?.batteryPercent ?? '--'}%' : '${latest!.batteryPercent}%')),
                              IconButton(onPressed: _refreshing ? null : _refresh, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh now'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_error != null)
                      Positioned(
                        left: 16,
                        right: 16,
                        top: 100,
                        child: Material(
                          color: ViraColors.dangerSoft,
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(_error!, style: const TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class PositionSnapshot {
  const PositionSnapshot({required this.latitude, required this.longitude, this.accuracyM});
  final double latitude;
  final double longitude;
  final double? accuracyM;
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: ViraColors.mutedPlum, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      );
}
