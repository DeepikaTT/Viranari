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

class SafetyCompassScreen extends StatefulWidget {
  const SafetyCompassScreen({super.key, required this.session});
  final AppSession session;

  @override
  State<SafetyCompassScreen> createState() => _SafetyCompassScreenState();
}

class _SafetyCompassScreenState extends State<SafetyCompassScreen>
    with WidgetsBindingObserver {
  final LocationService _location = LocationService();
  final SafeNodeCacheStore _cache = SafeNodeCacheStore();

  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _locationTimer;
  Position? _position;
  List<SafeNodePoint> _nodes = const [];
  SafeNodePoint? _selected;
  double? _heading;
  bool _loading = true;
  bool _usingCachedNodes = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenCompass();
    _refresh();
    _locationTimer = Timer.periodic(
      const Duration(seconds: 12),
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
      List<SafeNodePoint> nodes;
      var cached = false;
      try {
        nodes = await widget.session.api.nearbySafeNodes(
          latitude: position.latitude,
          longitude: position.longitude,
          radiusM: 25000,
        );
        if (nodes.isNotEmpty) await _cache.save(nodes);
      } catch (_) {
        nodes = await _cache.load();
        cached = true;
      }

      nodes = nodes.where((node) {
        final d = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          node.latitude,
          node.longitude,
        );
        return node.verified && d <= 25000;
      }).toList()
        ..sort((a, b) => _distanceTo(a, position).compareTo(_distanceTo(b, position)));

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
        _usingCachedNodes = cached;
        _loading = false;
        _error = null;
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
        return 'Hospital';
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
        return 'Safe Node';
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
    if (phone == null) return;
    await launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication);
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
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh GPS and Safe Nodes',
          ),
        ],
      ),
      body: _loading && position == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && position == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : target == null || position == null
                  ? _EmptyCompass(usingCache: _usingCachedNodes)
                  : _CompassBody(
                      node: target,
                      nodes: _nodes,
                      heading: _heading,
                      bearing: _bearingTo(target, position),
                      categoryLabel: _category(target.category),
                      distanceText: _distanceText(_distanceTo(target, position)),
                      usingCachedNodes: _usingCachedNodes,
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
    required this.usingCachedNodes,
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
  final bool usingCachedNodes;
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
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
        children: [
          const Text(
            'Move toward verified human help',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: ViraColors.plum),
          ),
          const SizedBox(height: 8),
          Text(
            usingCachedNodes
                ? 'Using Safe Nodes cached earlier on this phone.'
                : 'GPS + device compass. Safe Nodes come from the verified ViraNari directory.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: ViraColors.mutedPlum),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: ViraColors.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SafeNodePoint>(
                value: node,
                isExpanded: true,
                items: nodes
                    .take(12)
                    .map(
                      (n) => DropdownMenuItem(
                        value: n,
                        child: Text('${n.name} · ${n.approxDistanceM >= 1000 ? '${(n.approxDistanceM / 1000).toStringAsFixed(1)} km' : '${n.approxDistanceM} m'}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onNodeSelected(value);
                },
              ),
            ),
          ),
          const SizedBox(height: 26),
          Center(
            child: SizedBox(
              width: 270,
              height: 270,
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
                  const Positioned(top: 14, child: Text('N', style: TextStyle(fontWeight: FontWeight.w900))),
                  Transform.rotate(
                    angle: angle,
                    child: const Icon(
                      Icons.navigation_rounded,
                      size: 150,
                      color: ViraColors.pinkDark,
                    ),
                  ),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: ViraColors.plum),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            distanceText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: ViraColors.plum),
          ),
          const SizedBox(height: 5),
          Text(
            node.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          Text(
            '$categoryLabel · ${_direction(bearing)} · bearing ${bearing.toStringAsFixed(0)}°',
            textAlign: TextAlign.center,
            style: const TextStyle(color: ViraColors.mutedPlum),
          ),
          if (heading == null) ...[
            const SizedBox(height: 10),
            const Text(
              'Compass heading is unavailable. Move the phone in a figure-eight to calibrate; the distance and map button still work.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ViraColors.warning, fontWeight: FontWeight.w700),
            ),
          ],
          if (node.address != null) ...[
            const SizedBox(height: 10),
            Text(node.address!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 22),
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
  const _EmptyCompass({required this.usingCache});
  final bool usingCache;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_outlined, size: 62, color: ViraColors.mutedPlum),
            const SizedBox(height: 14),
            const Text(
              'No verified Safe Node is configured nearby',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              usingCache
                  ? 'The phone is offline and the cached Safe Node list has no verified place within 25 km.'
                  : 'A server operator must verify real police, hospital, campus-security, pharmacy, or staffed locations before ViraNari points a victim toward them.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: ViraColors.mutedPlum, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
