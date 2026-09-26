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
import '../services/safe_place_discovery_service.dart';
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
  final SafeNodeCacheStore _safeNodeCache = SafeNodeCacheStore();
  final SafePlaceDiscoveryService _publicPlaces = SafePlaceDiscoveryService();
  final MapController _mapController = MapController();

  Timer? _timer;
  Position? _position;
  List<PresencePoint> _presence = const [];
  List<SafeNodePoint> _safeNodes = const [];
  bool _enabled = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _followMe = true;
  bool _usingPublicPlaces = false;
  String? _error;
  static const int _safePlaceRadiusM = 15000;
  int _peopleRadiusM = 2000;
  bool _initialSafePlaceFitDone = false;
  DateTime? _lastUpdated;
  DateTime? _lastPublicLookup;

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

  SafeNodePoint _recalculateSafeNode(Position position, SafeNodePoint node) {
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      node.latitude,
      node.longitude,
    );
    final bearing = (Geolocator.bearingBetween(
              position.latitude,
              position.longitude,
              node.latitude,
              node.longitude,
            ) +
            360) %
        360;
    return SafeNodePoint(
      id: node.id,
      name: node.name,
      category: node.category,
      latitude: node.latitude,
      longitude: node.longitude,
      phoneE164: node.phoneE164,
      address: node.address,
      verified: node.verified,
      approxDistanceM: distance.round(),
      bearingDeg: bearing.round() % 360,
    );
  }

  List<SafeNodePoint> _recalculateSafeNodes(
    Position position,
    Iterable<SafeNodePoint> nodes,
  ) =>
      nodes
          .map((node) => _recalculateSafeNode(position, node))
          .toList(growable: false);

  Future<List<SafeNodePoint>> _loadSafePlaces(Position position) async {
    final verified = <SafeNodePoint>[];
    final publicPlaces = <SafeNodePoint>[];

    // V1.8.3 keeps verified Safe Nodes and public safety places in one rich map.
    // A single verified node must never suppress nearby hospitals/police/etc.
    try {
      verified.addAll(
        await widget.session.api.nearbySafeNodes(
          latitude: position.latitude,
          longitude: position.longitude,
          radiusM: _safePlaceRadiusM,
        ),
      );
    } catch (_) {
      // Public/cached places can still keep the Safety Map useful.
    }

    final shouldRefreshPublic = _lastPublicLookup == null ||
        DateTime.now().difference(_lastPublicLookup!) >
            const Duration(minutes: 5);

    if (shouldRefreshPublic) {
      try {
        publicPlaces.addAll(
          await _publicPlaces.discover(
            latitude: position.latitude,
            longitude: position.longitude,
            radiusM: _safePlaceRadiusM,
          ),
        );
        _lastPublicLookup = DateTime.now();
      } catch (_) {
        _lastPublicLookup = DateTime.now();
      }
    } else {
      publicPlaces.addAll(_safeNodes.where((node) => !node.verified));
    }

    if (publicPlaces.isEmpty) {
      final cached = await _safeNodeCache.load();
      publicPlaces.addAll(cached.where((node) => !node.verified));
      if (verified.isEmpty) {
        verified.addAll(cached.where((node) => node.verified));
      }
    }

    final recalculatedVerified = _recalculateSafeNodes(position, verified);
    final recalculatedPublic = _recalculateSafeNodes(position, publicPlaces);

    final merged = <SafeNodePoint>[];
    for (final node in recalculatedVerified) {
      if (node.approxDistanceM <= _safePlaceRadiusM) merged.add(node);
    }

    // Prefer a verified entry when OpenStreetMap has effectively the same place.
    for (final node in recalculatedPublic) {
      if (node.approxDistanceM > _safePlaceRadiusM) continue;
      final duplicateVerified = merged.any((existing) {
        if (!existing.verified || existing.category != node.category) return false;
        final d = Geolocator.distanceBetween(
          existing.latitude,
          existing.longitude,
          node.latitude,
          node.longitude,
        );
        return d < 80;
      });
      if (!duplicateVerified) merged.add(node);
    }

    merged.sort((a, b) => a.approxDistanceM.compareTo(b.approxDistanceM));
    _usingPublicPlaces = merged.any((node) => !node.verified);

    if (merged.isNotEmpty) {
      await _safeNodeCache.save(merged);
      return merged;
    }

    _usingPublicPlaces = false;
    return const [];
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

      List<PresencePoint> presence = const [];
      Object? presenceError;
      if (enabled) {
        try {
          presence = await widget.session.api.nearbyPresence(
            deviceId: deviceId,
            latitude: position.latitude,
            longitude: position.longitude,
            radiusM: _peopleRadiusM,
          );
        } catch (e) {
          presenceError = e;
        }
      }

      final safeNodes = await _loadSafePlaces(position);

      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _position = position;
        _presence = presence;
        _safeNodes = safeNodes;
        _lastUpdated = DateTime.now();
        _loading = false;
        _error = presenceError?.toString();
      });

      if (!_initialSafePlaceFitDone && safeNodes.isNotEmpty) {
        _initialSafePlaceFitDone = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _fitSafePlaces(position, safeNodes);
        });
      } else if (_followMe) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _mapController.move(
            LatLng(position.latitude, position.longitude),
            _zoomForRadius(_peopleRadiusM),
          );
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

  double _zoomForRadius(int radius) {
    if (radius <= 500) return 15.5;
    if (radius <= 2000) return 13.7;
    if (radius <= 5000) return 12.3;
    if (radius <= 10000) return 11.3;
    return 10.7;
  }

  void _fitSafePlaces(Position me, Iterable<SafeNodePoint> nodes) {
    var farthest = 2000;
    for (final node in nodes) {
      farthest = math.max(farthest, node.approxDistanceM);
    }
    farthest = math.min(farthest, _safePlaceRadiusM);
    _followMe = false;
    _mapController.move(
      LatLng(me.latitude, me.longitude),
      _zoomForRadius(farthest),
    );
  }

  Future<void> _setPeopleRadius(int radius) async {
    if (radius == _peopleRadiusM) {
      final me = _position;
      if (me != null) {
        _followMe = true;
        _mapController.move(
          LatLng(me.latitude, me.longitude),
          _zoomForRadius(radius),
        );
      }
      return;
    }

    setState(() {
      _peopleRadiusM = radius;
      _followMe = true;
      // Immediately hide dots outside the newly selected radius even before
      // the network refresh finishes.
      _presence = _presence
          .where((point) => point.approxDistanceM <= radius)
          .toList(growable: false);
    });

    final me = _position;
    if (me != null) {
      _mapController.move(
        LatLng(me.latitude, me.longitude),
        _zoomForRadius(radius),
      );
    }

    // If the periodic refresh is currently in-flight, wait briefly instead
    // of dropping this user-requested radius change. This matters when
    // expanding 500 m -> 2 km/5 km because new dots must be queried.
    for (var i = 0; i < 20 && _refreshing; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await _refresh(silent: true);
    if (!mounted) return;
    final refreshedMe = _position;
    if (refreshedMe != null) {
      _mapController.move(
        LatLng(refreshedMe.latitude, refreshedMe.longitude),
        _zoomForRadius(radius),
      );
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

  IconData _safeNodeIcon(String category) {
    switch (category.toLowerCase()) {
      case 'police':
        return Icons.local_police_rounded;
      case 'hospital':
        return Icons.local_hospital_rounded;
      case 'pharmacy':
        return Icons.local_pharmacy_rounded;
      case 'campus_security':
      case 'security':
        return Icons.security_rounded;
      case 'hostel_security':
        return Icons.home_work_rounded;
      case 'petrol_pump':
        return Icons.local_gas_station_rounded;
      case 'staffed_place':
        return Icons.local_fire_department_rounded;
      default:
        return Icons.health_and_safety_rounded;
    }
  }

  String _safeNodeShortLabel(String category) {
    switch (category.toLowerCase()) {
      case 'police':
        return 'Police';
      case 'hospital':
        return 'Hospital';
      case 'pharmacy':
        return 'Pharmacy';
      case 'campus_security':
      case 'security':
        return 'Security';
      case 'petrol_pump':
        return 'Fuel';
      case 'staffed_place':
        return 'Help';
      default:
        return 'Safe';
    }
  }

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
            Text(
              '${_distanceText(point.approxDistanceM)} away · ${_ageText(point.ageSeconds)}',
            ),
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
      return Scaffold(
        appBar: AppBar(title: const Text('Safety Map')),
        body: const Center(child: CircularProgressIndicator()),
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
                FilledButton(
                  onPressed: _refreshing ? null : _refresh,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final center = LatLng(me.latitude, me.longitude);
    final visiblePresence = _presence
        .where((point) => point.approxDistanceM <= _peopleRadiusM)
        .toList(growable: false);
    // Safety places are intentionally independent from the anonymous-people
    // radius. The 500 m / 2 km / 5 km selector controls people only.
    final visibleSafeNodes = _safeNodes
        .where((node) => node.approxDistanceM <= _safePlaceRadiusM)
        .toList(growable: false);
    final hospitalCount = visibleSafeNodes
        .where((node) => node.category == 'hospital')
        .length;
    final policeCount = visibleSafeNodes
        .where((node) => node.category == 'police')
        .length;
    final pharmacyCount = visibleSafeNodes
        .where((node) => node.category == 'pharmacy')
        .length;

    final presenceMarkers = _enabled
        ? visiblePresence
            .map(
              (point) => Marker(
                point: _projectPoint(me, point),
                width: 46,
                height: 46,
                child: GestureDetector(
                  onTap: () => _showPresence(point),
                  child: Center(
                    child: Container(
                      width: 17,
                      height: 17,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ViraColors.pink,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(blurRadius: 9, color: Colors.black26),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList()
        : <Marker>[];

    final safeMarkers = visibleSafeNodes
        .map(
          (node) => Marker(
            point: LatLng(node.latitude, node.longitude),
            width: 76,
            height: 70,
            child: GestureDetector(
              onTap: () => _openSafeNode(node),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: const Alignment(0, -0.12),
                    children: [
                      Icon(
                        Icons.location_pin,
                        size: 48,
                        color: node.verified ? ViraColors.plum : ViraColors.warning,
                        shadows: const [
                          Shadow(blurRadius: 8, color: Colors.black38),
                        ],
                      ),
                      Icon(
                        _safeNodeIcon(node.category),
                        color: Colors.white,
                        size: 19,
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: ViraColors.surface.withValues(alpha: .92),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      _safeNodeShortLabel(node.category),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: ViraColors.plum,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Safety Map', style: TextStyle(fontWeight: FontWeight.w900)),
            Text(
              'Anonymous live presence',
              style: TextStyle(fontSize: 11, color: ViraColors.mutedPlum),
            ),
          ],
        ),
        actions: [
          Switch.adaptive(
            value: _enabled,
            onChanged: _togglePresence,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: _zoomForRadius(_peopleRadiusM),
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
                                    boxShadow: const [
                                      BoxShadow(blurRadius: 8, color: Colors.black26),
                                    ],
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
                            onTap: () => launchUrl(
                              Uri.parse('https://www.openstreetmap.org/copyright'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'recenter',
                        backgroundColor: Colors.white,
                        foregroundColor: ViraColors.plum,
                        onPressed: () {
                          setState(() => _followMe = true);
                          _mapController.move(center, _zoomForRadius(_peopleRadiusM));
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
                      const SizedBox(height: 8),
                      Tooltip(
                        message: 'Show all safety places',
                        child: FloatingActionButton.small(
                          heroTag: 'fit_safe_places',
                          backgroundColor: Colors.white,
                          foregroundColor: ViraColors.plum,
                          onPressed: () {
                            if (visibleSafeNodes.isEmpty) return;
                            setState(() => _followMe = false);
                            _fitSafePlaces(me, visibleSafeNodes);
                          },
                          child: const Icon(Icons.zoom_out_map_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Positioned(
                    left: 12,
                    right: 70,
                    top: 12,
                    child: Material(
                      color: ViraColors.surface.withValues(alpha: .96),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          _error!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ViraColors.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: const BoxDecoration(
                color: ViraColors.surface,
                border: Border(
                  top: BorderSide(color: ViraColors.lilacStrong),
                ),
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
                              ? '${visiblePresence.length} anonymous device${visiblePresence.length == 1 ? '' : 's'} within ${_peopleRadiusM == 500 ? '500 m' : '${_peopleRadiusM ~/ 1000} km'}'
                              : 'Turn on anonymous presence to see nearby dots',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (_lastUpdated != null)
                        Text(
                          '${DateTime.now().difference(_lastUpdated!).inSeconds}s',
                          style: const TextStyle(
                            color: ViraColors.mutedPlum,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                  if (visibleSafeNodes.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _usingPublicPlaces
                            ? '${visibleSafeNodes.length} safety places within 15 km · $hospitalCount hospital/clinic · $policeCount police · $pharmacyCount pharmacy · amber = public'
                            : '${visibleSafeNodes.length} verified Safe Node${visibleSafeNodes.length == 1 ? '' : 's'} within 15 km',
                        style: const TextStyle(
                          color: ViraColors.mutedPlum,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 9),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Anonymous people radius',
                      style: TextStyle(
                        color: ViraColors.mutedPlum,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<int>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: 500, label: Text('500m')),
                              ButtonSegment(value: 2000, label: Text('2km')),
                              ButtonSegment(value: 5000, label: Text('5km')),
                            ],
                            selected: {_peopleRadiusM},
                            onSelectionChanged: (value) {
                              // Radius changes both the anonymous-device query
                              // and the visible map zoom immediately. Safety
                              // place pins remain independent and stay visible.
                              unawaited(_setPeopleRadius(value.first));
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _openCompass,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        child: const Icon(Icons.explore_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
