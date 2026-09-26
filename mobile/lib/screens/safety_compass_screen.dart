import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/session.dart';
import '../core/storage.dart';
import '../core/theme.dart';
import '../services/location_service.dart';
import '../services/safe_place_discovery_service.dart';

class SafetyCompassScreen extends StatefulWidget {
  const SafetyCompassScreen({super.key, required this.session});
  final AppSession session;

  @override
  State<SafetyCompassScreen> createState() => _SafetyCompassScreenState();
}

enum _NodeSource { verified, publicMap, cache }

class _SafetyCompassScreenState extends State<SafetyCompassScreen>
    with WidgetsBindingObserver {
  final LocationService _location = LocationService();
  final SafeNodeCacheStore _cache = SafeNodeCacheStore();
  final SafePlaceDiscoveryService _publicPlaces = SafePlaceDiscoveryService();

  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _locationTimer;
  Position? _position;
  List<SafeNodePoint> _nodes = const [];
  SafeNodePoint? _selected;
  double? _heading;
  bool _loading = true;
  String? _error;
  _NodeSource _source = _NodeSource.verified;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenCompass();
    _refresh();
    _locationTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_refresh(silent: true)),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  void _listenCompass() {
    final events = FlutterCompass.events;
    if (events == null) return;
    _compassSubscription = events.listen((event) {
      if (!mounted) return;
      final heading = event.heading;
      if (heading != null && heading.isFinite) {
        setState(() => _heading = (heading + 360) % 360);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _compassSubscription?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final position = await _location.current();
      var nodes = <SafeNodePoint>[];
      var source = _NodeSource.verified;
      Object? backendError;
      Object? publicError;

      // 1) Prefer ViraNari operator-verified Safe Nodes.
      try {
        nodes = await widget.session.api.nearbySafeNodes(
          latitude: position.latitude,
          longitude: position.longitude,
          radiusM: 25000,
        );
      } catch (e) {
        backendError = e;
      }

      // 2) If none exist, automatically discover real public emergency places
      // from OpenStreetMap. These are shown as PUBLIC, not VERIFIED.
      if (nodes.isEmpty) {
        try {
          nodes = await _publicPlaces.discover(
            latitude: position.latitude,
            longitude: position.longitude,
            radiusM: 15000,
          );
          if (nodes.isNotEmpty) source = _NodeSource.publicMap;
        } catch (e) {
          publicError = e;
        }
      }

      // 3) Offline / service failure fallback: reuse whatever was cached from a
      // previous successful lookup.
      if (nodes.isEmpty) {
        final cached = await _cache.load();
        nodes = cached.where((node) {
          final d = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            node.latitude,
            node.longitude,
          );
          return d <= 25000;
        }).toList();
        if (nodes.isNotEmpty) source = _NodeSource.cache;
      }

      nodes = nodes.where((node) {
        final d = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          node.latitude,
          node.longitude,
        );
        return d <= 25000;
      }).toList()
        ..sort((a, b) => _distanceTo(a, position).compareTo(_distanceTo(b, position)));

      if (nodes.isNotEmpty) {
        await _cache.save(nodes);
      }

      final selectedId = _selected?.id;
      SafeNodePoint? selected;
      if (selectedId != null && nodes.any((node) => node.id == selectedId)) {
        selected = nodes.firstWhere((node) => node.id == selectedId);
      } else {
        selected = nodes.isEmpty ? null : nodes.first;
      }

      if (!mounted) return;
      setState(() {
        _position = position;
        _nodes = nodes;
        _selected = selected;
        _source = source;
        _loading = false;
        _error = nodes.isEmpty
            ? [
                if (backendError != null) 'ViraNari directory: $backendError',
                if (publicError != null) 'Public-place lookup: $publicError',
              ].join('\n')
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.toString();
      });
    }
  }

  double _distanceTo(SafeNodePoint node, Position position) =>
      Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        node.latitude,
        node.longitude,
      );

  double _bearingTo(SafeNodePoint node, Position position) =>
      (Geolocator.bearingBetween(
                position.latitude,
                position.longitude,
                node.latitude,
                node.longitude,
              ) +
              360) %
          360;

  String _distanceText(double metres) => metres >= 1000
      ? '${(metres / 1000).toStringAsFixed(1)} km'
      : '${metres.toStringAsFixed(0)} m';

  String _category(String raw) {
    switch (raw) {
      case 'police':
        return 'Police';
      case 'hospital':
        return 'Hospital / clinic';
      case 'pharmacy':
        return 'Pharmacy';
      case 'campus_security':
        return 'Campus security';
      case 'hostel_desk':
        return 'Hostel/security desk';
      case 'petrol_pump':
        return 'Petrol pump';
      case 'staffed_place':
        return 'Staffed safe place';
      default:
        return 'Safety place';
    }
  }

  String get _sourceLabel {
    switch (_source) {
      case _NodeSource.verified:
        return 'ViraNari verified';
      case _NodeSource.publicMap:
        return 'Public place from OpenStreetMap · not ViraNari verified';
      case _NodeSource.cache:
        return 'Cached safety place · verify before relying on it';
    }
  }

  Color get _sourceColor {
    switch (_source) {
      case _NodeSource.verified:
        return ViraColors.success;
      case _NodeSource.publicMap:
        return ViraColors.warning;
      case _NodeSource.cache:
        return ViraColors.mutedPlum;
    }
  }

  Future<void> _openMap(SafeNodePoint node) async {
    final uri = Uri.parse(
      'geo:${node.latitude},${node.longitude}?q=${node.latitude},${node.longitude}(${Uri.encodeComponent(node.name)})',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _call(SafeNodePoint node) async {
    final phone = node.phoneE164;
    if (phone == null || phone.trim().isEmpty) return;
    await launchUrl(
      Uri(scheme: 'tel', path: phone),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openEmergencySearch() async {
    final position = _position;
    if (position == null) return;
    final uri = Uri.parse(
      'geo:${position.latitude},${position.longitude}?q=${Uri.encodeComponent('police hospital pharmacy near me')}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    final target = _selected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Compass'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh GPS and safety places',
          ),
        ],
      ),
      body: _loading && position == null
          ? const Center(child: CircularProgressIndicator())
          : target == null || position == null
              ? _EmptyCompass(
                  error: _error,
                  onRefresh: () => _refresh(),
                  onOpenSearch: position == null ? null : _openEmergencySearch,
                )
              : _CompassBody(
                  node: target,
                  nodes: _nodes,
                  heading: _heading,
                  bearing: _bearingTo(target, position),
                  categoryLabel: _category(target.category),
                  distanceText: _distanceText(_distanceTo(target, position)),
                  sourceLabel: _sourceLabel,
                  sourceColor: _sourceColor,
                  onNodeSelected: (node) => setState(() => _selected = node),
                  onMap: () => _openMap(target),
                  onCall: target.phoneE164 == null ? null : () => _call(target),
                ),
    );
  }
}

class _CompassBody extends StatelessWidget {
  const _CompassBody({
    required this.node,
    required this.nodes,
    required this.heading,
    required this.bearing,
    required this.categoryLabel,
    required this.distanceText,
    required this.sourceLabel,
    required this.sourceColor,
    required this.onNodeSelected,
    required this.onMap,
    required this.onCall,
  });

  final SafeNodePoint node;
  final List<SafeNodePoint> nodes;
  final double? heading;
  final double bearing;
  final String categoryLabel;
  final String distanceText;
  final String sourceLabel;
  final Color sourceColor;
  final ValueChanged<SafeNodePoint> onNodeSelected;
  final VoidCallback onMap;
  final VoidCallback? onCall;

  String _direction(double deg) {
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return labels[((deg + 22.5) ~/ 45) % 8];
  }

  @override
  Widget build(BuildContext context) {
    final relative = heading == null ? bearing : (bearing - heading! + 360) % 360;
    final angle = relative * math.pi / 180;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: sourceColor.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: sourceColor.withValues(alpha: .30)),
            ),
            child: Row(
              children: [
                Icon(
                  node.verified ? Icons.verified_rounded : Icons.public_rounded,
                  color: sourceColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sourceLabel,
                    style: TextStyle(
                      color: sourceColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: ViraColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ViraColors.lilacStrong),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SafeNodePoint>(
                value: node,
                isExpanded: true,
                items: nodes
                    .take(20)
                    .map(
                      (n) => DropdownMenuItem(
                        value: n,
                        child: Text(
                          '${n.name} · ${n.approxDistanceM >= 1000 ? '${(n.approxDistanceM / 1000).toStringAsFixed(1)} km' : '${n.approxDistanceM} m'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onNodeSelected(value);
                },
              ),
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: SizedBox(
              width: 255,
              height: 255,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ViraColors.lilac,
                      border: Border.all(color: ViraColors.lilacStrong, width: 2),
                    ),
                  ),
                  const Positioned(
                    top: 12,
                    child: Text('N', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  const Positioned(
                    bottom: 12,
                    child: Text('S', style: TextStyle(fontWeight: FontWeight.w700, color: ViraColors.mutedPlum)),
                  ),
                  const Positioned(
                    left: 14,
                    child: Text('W', style: TextStyle(fontWeight: FontWeight.w700, color: ViraColors.mutedPlum)),
                  ),
                  const Positioned(
                    right: 14,
                    child: Text('E', style: TextStyle(fontWeight: FontWeight.w700, color: ViraColors.mutedPlum)),
                  ),
                  Transform.rotate(
                    angle: angle,
                    child: const Icon(
                      Icons.navigation_rounded,
                      size: 138,
                      color: ViraColors.pinkDark,
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: ViraColors.plum,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            distanceText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: ViraColors.plum,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            node.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            '$categoryLabel · ${_direction(bearing)} · ${bearing.toStringAsFixed(0)}°',
            textAlign: TextAlign.center,
            style: const TextStyle(color: ViraColors.mutedPlum),
          ),
          if (heading == null) ...[
            const SizedBox(height: 10),
            const Text(
              'Compass sensor is not reporting a heading yet. Move the phone in a figure-eight to calibrate it. Distance and Open map still work.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ViraColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (node.address != null && node.address!.trim().isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(node.address!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onMap,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Open map'),
                ),
              ),
              if (onCall != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCall,
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Call'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyCompass extends StatelessWidget {
  const _EmptyCompass({
    required this.error,
    required this.onRefresh,
    required this.onOpenSearch,
  });

  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenSearch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.explore_off_outlined,
              size: 62,
              color: ViraColors.mutedPlum,
            ),
            const SizedBox(height: 14),
            const Text(
              'No safety place was found nearby',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'ViraNari first checks operator-verified Safe Nodes, then falls back to public police, hospital, clinic and pharmacy data from OpenStreetMap. Successful results are cached for later use.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ViraColors.mutedPlum, height: 1.4),
            ),
            if (error != null && error!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: ViraColors.warning, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
            if (onOpenSearch != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onOpenSearch,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Search nearby help in Maps'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}