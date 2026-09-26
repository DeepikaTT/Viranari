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
  int _radiusM = 2000;
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
    try {
      final verified = await widget.session.api.nearbySafeNodes(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusM: 10000,
      );
      if (verified.isNotEmpty) {
        _usingPublicPlaces = false;
        final recalculated = _recalculateSafeNodes(position, verified);
        await _safeNodeCache.save(recalculated);
        return recalculated;
      }
    } catch (_) {
      // Continue to public/cached fallback below.
    }

    final shouldRefreshPublic = _lastPublicLookup == null ||
        DateTime.now().difference(_lastPublicLookup!) > const Duration(minutes: 5);

    if (shouldRefreshPublic) {
      try {
        final public = await _publicPlaces.discover(
          latitude: position.latitude,
          longitude: position.longitude,
          radiusM: 10000,
        );
        _lastPublicLookup = DateTime.now();
        if (public.isNotEmpty) {
          _usingPublicPlaces = true;
          final recalculated = _recalculateSafeNodes(position, public);
          await _safeNodeCache.save(recalculated);
          return recalculated;
        }
      } catch (_) {
        _lastPublicLookup = DateTime.now();
      }
    } else if (_safeNodes.isNotEmpty && _usingPublicPlaces) {
      return _recalculateSafeNodes(position, _safeNodes);
    }

    final cached = await _safeNodeCache.load();
    final nearby = cached.where((node) {
      final d = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        node.latitude,
        node.longitude,
      );
      return d <= 10000;
    }).toList();
    if (nearby.isNotEmpty) {
      final recalculated = _recalculateSafeNodes(position, nearby);
      _usingPublicPlaces = recalculated.any((node) => !node.verified);
      return recalculated;
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
            radiusM: _radiusM,
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

      if (_followMe) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _mapController.move(
            LatLng(position.latitude, position.longitude),
            _zoomForRadius(_radiusM),
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
    // Show roughly the full diameter, not just the centre of the selected
    // search radius. This makes 500 m / 2 km / 5 km controls visibly distinct.
    if (radius <= 500) return 15.5;
    if (radius <= 2000) return 13.7;
    return 12.3;
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
    final visibleSafeNodes = _safeNodes
        .where((node) => node.approxDistanceM <= _radiusM)
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
                      initialZoom: _zoomForRadius(_radiusM),
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
                          _mapController.move(center, _zoomForRadius(_radiusM));
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
                              ? '${_presence.length} anonymous device${_presence.length == 1 ? '' : 's'} nearby'
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
                            ? '${visibleSafeNodes.length} public places · $hospitalCount hospital · $policeCount police · $pharmacyCount pharmacy · amber = public'
                            : '${visibleSafeNodes.length} verified Safe Node${visibleSafeNodes.length == 1 ? '' : 's'} within ${_distanceText(_radiusM)}',
                        style: const TextStyle(
                          color: ViraColors.mutedPlum,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 9),
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
                            selected: {_radiusM},
                            onSelectionChanged: (value) {
                              final radius = value.first;
                              setState(() {
                                _radiusM = radius;
                                _followMe = true;
                              });
                              _mapController.move(center, _zoomForRadius(radius));
                              unawaited(_refresh());
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
