import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/session.dart';
import '../core/storage.dart';
import '../core/theme.dart';
import '../services/location_service.dart';
import 'safety_compass_screen.dart';

class SafetyMapScreen extends StatefulWidget {
  const SafetyMapScreen({super.key, required this.session});
  final AppSession session;

  @override
  State<SafetyMapScreen> createState() => _SafetyMapScreenState();
}

class _SafetyMapScreenState extends State<SafetyMapScreen>
    with WidgetsBindingObserver {
  final LocationService _location = LocationService();
  final SafetySettingsStore _settings = SafetySettingsStore();
  final MapController _mapController = MapController();

  Timer? _timer;
  Position? _position;
  List<PresencePoint> _presence = const [];
  List<SafeNodePoint> _safeNodes = const [];
  bool _enabled = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _followMe = true;
  String? _error;
  int _radiusM = 2000;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(
      const Duration(seconds: 7),
      (_) => unawaited(_refresh(silent: true)),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
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
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final enabled = await _settings.safetyPresenceEnabled();
      final deviceId = await _settings.installationId();
      final position = await _location.current();

      if (enabled) {
        await widget.session.api.updatePresence(
          deviceId: deviceId,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }

      final results = await Future.wait([
        enabled
            ? widget.session.api.nearbyPresence(
                deviceId: deviceId,
                latitude: position.latitude,
                longitude: position.longitude,
                radiusM: _radiusM,
              )
            : Future<List<PresencePoint>>.value(const []),
        widget.session.api.nearbySafeNodes(
          latitude: position.latitude,
          longitude: position.longitude,
          radiusM: 10000,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _position = position;
        _presence = results[0] as List<PresencePoint>;
        _safeNodes = results[1] as List<SafeNodePoint>;
        _lastUpdated = DateTime.now();
        _loading = false;
        _error = null;
      });

      if (_followMe) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mapController.move(
              LatLng(position.latitude, position.longitude),
              _radiusM <= 500 ? 16.5 : _radiusM <= 2000 ? 14.8 : 13.5,
            );
          }
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

  Future<void> _togglePresence(bool value) async {
    try {
      final deviceId = await _settings.installationId();
      if (!value) {
        await widget.session.api.disablePresence(deviceId);
        await _settings.setSafetyPresenceEnabled(false);
      } else {
        final position = await _location.current();
        await widget.session.api.updatePresence(
          deviceId: deviceId,
          latitude: position.latitude,
          longitude: position.longitude,
        );
        await _settings.setSafetyPresenceEnabled(true);
      }
      if (mounted) setState(() => _enabled = value);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not change anonymous presence: $e')),
        );
      }
    }
  }

  LatLng _projectPoint(Position me, PresencePoint point) {
    const earthRadiusM = 6371000.0;
    final distance = point.approxDistanceM.toDouble();
    final bearing = point.bearingDeg * math.pi / 180.0;
    final lat1 = me.latitude * math.pi / 180.0;
    final lon1 = me.longitude * math.pi / 180.0;
    final angular = distance / earthRadiusM;

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angular) +
          math.cos(lat1) * math.sin(angular) * math.cos(bearing),
    );
    final lon2 = lon1 +
        math.atan2(
          math.sin(bearing) * math.sin(angular) * math.cos(lat1),
          math.cos(angular) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(lat2 * 180.0 / math.pi, lon2 * 180.0 / math.pi);
  }

  String _ageText(int seconds) {
    if (seconds < 10) return 'active now';
    if (seconds < 60) return '${seconds}s ago';
    return '${seconds ~/ 60}m ago';
  }

  String _distanceText(int metres) => metres >= 1000
      ? '${(metres / 1000).toStringAsFixed(1)} km'
      : '~$metres m';

  void _showPresence(PresencePoint point) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Anonymous safety presence',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text('${_distanceText(point.approxDistanceM)} away · ${_ageText(point.ageSeconds)}'),
            const SizedBox(height: 10),
            const Text(
              'ViraNari does not reveal this person’s name, phone number, account, device ID, or exact coordinates.',
              style: TextStyle(color: ViraColors.mutedPlum, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSafeNode(SafeNodePoint node) async {
    final uri = Uri.parse(
      'geo:${node.latitude},${node.longitude}?q=${node.latitude},${node.longitude}(${Uri.encodeComponent(node.name)})',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openCompass() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SafetyCompassScreen(session: widget.session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _position;
    if (_loading && me == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Safety Map')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_off_outlined, size: 54),
                const SizedBox(height: 12),
                Text(_error ?? 'Location is unavailable.'),
                const SizedBox(height: 12),
                FilledButton(onPressed: _refreshing ? null : _refresh, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      );
    }

    final center = LatLng(me.latitude, me.longitude);
    final presenceMarkers = _enabled
        ? _presence
            .map(
              (point) => Marker(
                point: _projectPoint(me, point),
                width: 46,
                height: 46,
                child: GestureDetector(
                  onTap: () => _showPresence(point),
                  child: Center(
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ViraColors.pink,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [BoxShadow(blurRadius: 9, color: Colors.black26)],
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList()
        : <Marker>[];

    final safeMarkers = _safeNodes
        .map(
          (node) => Marker(
            point: LatLng(node.latitude, node.longitude),
            width: 48,
            height: 48,
            child: GestureDetector(
              onTap: () => _openSafeNode(node),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ViraColors.plum,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
                ),
                child: const Icon(Icons.shield_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),
        )
        .toList();

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14.8,
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture && _followMe && mounted) {
                    setState(() => _followMe = false);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.viranari.viranari_app',
                ),
                MarkerLayer(
                  markers: [
                    ...presenceMarkers,
                    ...safeMarkers,
                    Marker(
                      point: center,
                      width: 70,
                      height: 70,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ViraColors.plum.withValues(alpha: .14),
                        ),
                        child: Center(
                          child: Container(
                            width: 25,
                            height: 25,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ViraColors.plum,
                              border: Border.all(color: Colors.white, width: 4),
                              boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    elevation: 2,
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .95),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black12)],
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Safety Map', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                                Text('Anonymous live presence', style: TextStyle(fontSize: 11, color: ViraColors.mutedPlum)),
                              ],
                            ),
                          ),
                          Switch.adaptive(value: _enabled, onChanged: _togglePresence),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 14,
            top: MediaQuery.of(context).padding.top + 86,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'recenter',
                  backgroundColor: Colors.white,
                  foregroundColor: ViraColors.plum,
                  onPressed: () {
                    setState(() => _followMe = true);
                    _mapController.move(center, 14.8);
                  },
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'refresh',
                  backgroundColor: Colors.white,
                  foregroundColor: ViraColors.plum,
                  onPressed: _refreshing ? null : _refresh,
                  child: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 18,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .96),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [BoxShadow(blurRadius: 14, color: Colors.black12)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.circle, size: 11, color: ViraColors.pink),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _enabled
                                ? '${_presence.length} anonymous device${_presence.length == 1 ? '' : 's'} nearby'
                                : 'Turn on anonymous presence to participate and see nearby dots',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (_lastUpdated != null)
                          Text(
                            '${DateTime.now().difference(_lastUpdated!).inSeconds}s',
                            style: const TextStyle(color: ViraColors.mutedPlum, fontSize: 11),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<int>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: 500, label: Text('500m')),
                              ButtonSegment(value: 2000, label: Text('2km')),
                              ButtonSegment(value: 5000, label: Text('5km')),
                            ],
                            selected: {_radiusM},
                            onSelectionChanged: (value) {
                              setState(() => _radiusM = value.first);
                              unawaited(_refresh());
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _openCompass,
                          icon: const Icon(Icons.explore_rounded),
                          label: const Text('Compass'),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: ViraColors.pinkDark, fontSize: 12)),
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
