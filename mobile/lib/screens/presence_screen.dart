import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/session.dart';
import '../core/storage.dart';
import '../core/theme.dart';
import '../services/location_service.dart';

class SafetyPresenceScreen extends StatefulWidget {
  const SafetyPresenceScreen({super.key, required this.session});
  final AppSession session;

  @override
  State<SafetyPresenceScreen> createState() => _SafetyPresenceScreenState();
}

class _SafetyPresenceScreenState extends State<SafetyPresenceScreen> {
  final _location = LocationService();
  final _settings = SafetySettingsStore();
  bool _enabled = false;
  bool _loading = true;
  bool _refreshing = false;
  List<PresencePoint> _points = const [];
  String? _error;
  int _radiusM = 1500;
  Timer? _timer;
  DateTime? _lastBroadcast;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
    try {
      _enabled = await _settings.safetyPresenceEnabled();
      final deviceId = await _settings.installationId();
      final position = await _location.current();
      if (_enabled) {
        await widget.session.api.updatePresence(
          deviceId: deviceId,
          latitude: position.latitude,
          longitude: position.longitude,
        );
        _lastBroadcast = DateTime.now();
      }
      final points = await widget.session.api.nearbyPresence(
        deviceId: deviceId,
        latitude: position.latitude,
        longitude: position.longitude,
        radiusM: _radiusM,
      );
      if (mounted) setState(() { _points = points; _error = null; });
    } catch (e) {
      if (mounted && !silent) setState(() => _error = e.toString());
    } finally {
      _refreshing = false;
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool value) async {
    try {
      final deviceId = await _settings.installationId();
      if (value) {
        final position = await _location.current();
        await widget.session.api.updatePresence(
          deviceId: deviceId,
          latitude: position.latitude,
          longitude: position.longitude,
        );
        _lastBroadcast = DateTime.now();
      } else {
        await widget.session.api.disablePresence(deviceId);
      }
      await _settings.setSafetyPresenceEnabled(value);
      if (mounted) setState(() => _enabled = value);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  String get _radiusLabel => _radiusM >= 1000 ? '${(_radiusM / 1000).toStringAsFixed(1)} km' : '$_radiusM m';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Presence')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            Text('Who is within reach?', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: ViraColors.plum)),
            const SizedBox(height: 6),
            const Text(
              'Anonymous device presence only. No names, phone numbers, stable public IDs or exact public coordinates are returned.',
              style: TextStyle(color: ViraColors.mutedPlum, height: 1.4),
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: _toggle,
              title: const Text('Broadcast this phone anonymously', style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(_enabled
                  ? 'Active · refreshes about every 6 seconds while this screen is open.'
                  : 'Enable this on the other test phone too.'),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 500, label: Text('500 m')),
                ButtonSegment(value: 1500, label: Text('1.5 km')),
                ButtonSegment(value: 3000, label: Text('3 km')),
              ],
              selected: {_radiusM},
              onSelectionChanged: (value) {
                setState(() => _radiusM = value.first);
                _load();
              },
            ),
            const SizedBox(height: 18),
            AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ViraColors.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: ViraColors.lilacStrong),
                ),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : CustomPaint(
                        painter: _PresenceRadarPainter(points: _points, radiusM: _radiusM),
                        child: Center(
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: ViraColors.plum),
                            alignment: Alignment.center,
                            child: const Text('YOU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.radar_rounded, color: ViraColors.plum),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_points.length} other ViraNari device${_points.length == 1 ? '' : 's'} within $_radiusLabel',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(onPressed: _refreshing ? null : () => _load(), icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh now'),
              ],
            ),
            if (_enabled && _lastBroadcast != null)
              Text('This phone broadcast ${DateTime.now().difference(_lastBroadcast!).inSeconds < 10 ? 'just now' : '${DateTime.now().difference(_lastBroadcast!).inSeconds}s ago'}.',
                  style: const TextStyle(color: ViraColors.mutedPlum)),
            if (_points.isEmpty && !_loading) ...[
              const SizedBox(height: 10),
              const Text(
                'No dots yet. For a two-phone test, enable Safety Presence on BOTH phones. V1.4.1 is device-based, so even two phones signed into the same account can appear separately.',
                style: TextStyle(color: ViraColors.mutedPlum, height: 1.4),
              ),
            ],
            if (_points.isNotEmpty) ...[
              const SizedBox(height: 10),
              ..._points.take(8).map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 10, color: ViraColors.pink),
                        const SizedBox(width: 10),
                        Text('~${p.approxDistanceM} m away'),
                        const Spacer(),
                        Text('${p.ageSeconds}s ago', style: const TextStyle(color: ViraColors.mutedPlum)),
                      ],
                    ),
                  )),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}

class _PresenceRadarPainter extends CustomPainter {
  const _PresenceRadarPainter({required this.points, required this.radiusM});
  final List<PresencePoint> points;
  final int radiusM;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) * .43;
    final ringPaint = Paint()..color = ViraColors.lilacStrong..style = PaintingStyle.stroke..strokeWidth = 1.2;
    for (final f in [.33, .66, 1.0]) {
      canvas.drawCircle(center, maxRadius * f, ringPaint);
    }
    final dotPaint = Paint()..color = ViraColors.pink;
    for (final p in points) {
      final angle = (p.bearingDeg - 90) * math.pi / 180;
      final normalized = (p.approxDistanceM / radiusM).clamp(0.08, 1.0).toDouble();
      final r = maxRadius * normalized;
      final point = Offset(center.dx + math.cos(angle) * r, center.dy + math.sin(angle) * r);
      canvas.drawCircle(point, 7, dotPaint);
      canvas.drawCircle(point, 13, Paint()..color = ViraColors.pink.withValues(alpha: .15));
    }
  }

  @override
  bool shouldRepaint(covariant _PresenceRadarPainter oldDelegate) => oldDelegate.points != points || oldDelegate.radiusM != radiusM;
}
