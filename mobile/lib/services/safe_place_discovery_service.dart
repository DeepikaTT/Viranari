import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../core/models.dart';

/// Best-effort public-place fallback used only when the ViraNari backend has no
/// operator-verified Safe Nodes near the user.
///
/// Data comes from OpenStreetMap/Overpass. These results are intentionally
/// returned with verified=false so the UI never labels community-mapped places
/// as ViraNari-verified.
class SafePlaceDiscoveryService {
  static const _endpoints = <String>[
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  Future<List<SafeNodePoint>> discover({
    required double latitude,
    required double longitude,
    int radiusM = 12000,
  }) async {
    final boundedRadius = radiusM.clamp(1000, 25000);
    final query = '''
[out:json][timeout:10];
(
  node(around:$boundedRadius,$latitude,$longitude)["amenity"~"^(police|hospital|pharmacy|clinic|fire_station)\$"];
  way(around:$boundedRadius,$latitude,$longitude)["amenity"~"^(police|hospital|pharmacy|clinic|fire_station)\$"];
  relation(around:$boundedRadius,$latitude,$longitude)["amenity"~"^(police|hospital|pharmacy|clinic|fire_station)\$"];
);
out center tags;
''';

    Object? lastError;
    for (final endpoint in _endpoints) {
      try {
        final response = await http
            .post(
              Uri.parse(endpoint),
              headers: const {
                'Accept': 'application/json',
                'User-Agent': 'ViraNari/1.8 live-coordination',
              },
              body: {'data': query},
            )
            .timeout(const Duration(seconds: 11));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          lastError = 'OpenStreetMap lookup failed (${response.statusCode})';
          continue;
        }

        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final elements = decoded['elements'] as List<dynamic>? ?? const [];
        final out = <SafeNodePoint>[];
        final seen = <String>{};

        for (final raw in elements) {
          if (raw is! Map<String, dynamic>) continue;
          final tags = (raw['tags'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
          final amenity = tags['amenity']?.toString();
          if (amenity == null) continue;

          double? lat;
          double? lon;
          if (raw['lat'] is num && raw['lon'] is num) {
            lat = (raw['lat'] as num).toDouble();
            lon = (raw['lon'] as num).toDouble();
          } else {
            final center = raw['center'];
            if (center is Map && center['lat'] is num && center['lon'] is num) {
              lat = (center['lat'] as num).toDouble();
              lon = (center['lon'] as num).toDouble();
            }
          }
          if (lat == null || lon == null) continue;

          final distance = Geolocator.distanceBetween(latitude, longitude, lat, lon);
          if (!distance.isFinite || distance > boundedRadius) continue;
          final bearing = (Geolocator.bearingBetween(latitude, longitude, lat, lon) + 360) % 360;

          final type = raw['type']?.toString() ?? 'place';
          final id = raw['id']?.toString() ?? '${lat.toStringAsFixed(5)}_${lon.toStringAsFixed(5)}';
          final dedupe = '$type:$id';
          if (!seen.add(dedupe)) continue;

          out.add(
            SafeNodePoint(
              id: 'osm:$type:$id',
              name: _name(tags, amenity),
              category: _category(amenity),
              latitude: lat,
              longitude: lon,
              phoneE164: _phone(tags),
              address: _address(tags),
              verified: false,
              approxDistanceM: distance.round(),
              bearingDeg: bearing.round() % 360,
            ),
          );
        }

        out.sort((a, b) => a.approxDistanceM.compareTo(b.approxDistanceM));
        return out.take(30).toList(growable: false);
      } catch (e) {
        lastError = e;
      }
    }

    if (lastError != null) {
      throw StateError(lastError.toString());
    }
    return const [];
  }

  String _name(Map<String, dynamic> tags, String amenity) {
    final explicit = tags['name']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    switch (amenity) {
      case 'police':
        return 'Police station';
      case 'hospital':
        return 'Hospital';
      case 'pharmacy':
        return 'Pharmacy';
      case 'clinic':
        return 'Clinic';
      case 'fire_station':
        return 'Fire station';
      default:
        return 'Public safety place';
    }
  }

  String _category(String amenity) {
    switch (amenity) {
      case 'police':
        return 'police';
      case 'hospital':
      case 'clinic':
        return 'hospital';
      case 'pharmacy':
        return 'pharmacy';
      case 'fire_station':
        return 'staffed_place';
      default:
        return 'other';
    }
  }

  String? _phone(Map<String, dynamic> tags) {
    final raw = tags['contact:phone']?.toString() ?? tags['phone']?.toString();
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  String? _address(Map<String, dynamic> tags) {
    final full = tags['addr:full']?.toString().trim();
    if (full != null && full.isNotEmpty) return full;

    final parts = <String>[
      if ((tags['addr:housenumber']?.toString().trim() ?? '').isNotEmpty)
        tags['addr:housenumber'].toString().trim(),
      if ((tags['addr:street']?.toString().trim() ?? '').isNotEmpty)
        tags['addr:street'].toString().trim(),
      if ((tags['addr:suburb']?.toString().trim() ?? '').isNotEmpty)
        tags['addr:suburb'].toString().trim(),
      if ((tags['addr:city']?.toString().trim() ?? '').isNotEmpty)
        tags['addr:city'].toString().trim(),
    ];
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }
}
