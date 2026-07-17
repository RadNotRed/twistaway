import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoadSpeedLimitService {
  RoadSpeedLimitService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, _CachedSpeedLimit> _cache = {};
  final Map<String, Future<double?>> _inFlight = {};

  Future<double?> speedLimitMph(LatLng position) async {
    final key = _gridKey(position);
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) <
            const Duration(minutes: 10)) {
      return cached.milesPerHour;
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final request = _lookup(position, key);
    _inFlight[key] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<double?> _lookup(LatLng position, String key) async {
    final query =
        '[out:json][timeout:4];way(around:25,${position.latitude.toStringAsFixed(6)},${position.longitude.toStringAsFixed(6)})[highway][maxspeed];out tags 8;';
    final uri = Uri.https('overpass-api.de', '/api/interpreter', {
      'data': query,
    });
    final response = await _client.get(
      uri,
      headers: const {
        'User-Agent': 'Twistaway/0.1 (development contact: twistaway.local)',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = decoded['elements'] as List<dynamic>? ?? const [];
    final limits = elements
        .whereType<Map<String, dynamic>>()
        .map((element) => element['tags'])
        .whereType<Map<String, dynamic>>()
        .map((tags) => parseOsmMaxSpeed(tags['maxspeed']?.toString()))
        .whereType<double>()
        .map((limit) => limit.round())
        .toSet();
    final speedLimit = limits.length == 1 ? limits.single.toDouble() : null;
    _cache[key] = _CachedSpeedLimit(speedLimit, DateTime.now());
    return speedLimit;
  }

  String _gridKey(LatLng position) =>
      '${position.latitude.toStringAsFixed(4)},${position.longitude.toStringAsFixed(4)}';

  void close() => _client.close();
}

double? parseOsmMaxSpeed(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final normalized = value.trim().toLowerCase();
  if (normalized == 'none' ||
      normalized == 'signals' ||
      normalized == 'variable' ||
      normalized == 'walk') {
    return null;
  }
  final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(normalized);
  final number = double.tryParse(match?.group(1) ?? '');
  if (number == null || number <= 0) return null;
  if (normalized.contains('mph')) return number;
  return number * 0.621371;
}

bool isSpeedWarning({
  required double speedMph,
  required double? speedLimitMph,
  required double thresholdMph,
}) {
  return speedLimitMph != null &&
      speedMph > speedLimitMph &&
      speedMph - speedLimitMph >= thresholdMph;
}

class _CachedSpeedLimit {
  const _CachedSpeedLimit(this.milesPerHour, this.createdAt);

  final double? milesPerHour;
  final DateTime createdAt;
}
