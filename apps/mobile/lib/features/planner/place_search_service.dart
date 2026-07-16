import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/cache/expiring_lru_cache.dart';

class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.latLng,
    this.type,
    this.distanceMeters,
  });

  final String name;
  final LatLng latLng;
  final String? type;
  final double? distanceMeters;
}

class SearchContext {
  const SearchContext({
    this.center,
    this.north,
    this.south,
    this.east,
    this.west,
  });

  final LatLng? center;
  final double? north;
  final double? south;
  final double? east;
  final double? west;

  Map<String, String> toQueryParameters() => {
        if (center != null) 'centerLat': _coordinate(center!.latitude),
        if (center != null) 'centerLng': _coordinate(center!.longitude),
        if (north != null) 'north': _coordinate(north!),
        if (south != null) 'south': _coordinate(south!),
        if (east != null) 'east': _coordinate(east!),
        if (west != null) 'west': _coordinate(west!),
      };

  String _coordinate(double value) => value.toStringAsFixed(2);
}

class PlaceSearchService {
  PlaceSearchService({
    http.Client? client,
    ExpiringLruCache<String, List<PlaceResult>>? cache,
    String apiBaseUrl = const String.fromEnvironment(
      'TWISTAWAY_API_BASE_URL',
      defaultValue: 'http://localhost:4180',
    ),
    bool? useDirectProviders,
  })  : _client = client ?? http.Client(),
        _cache = cache ??
            ExpiringLruCache(
              maximumEntries: 48,
              timeToLive: const Duration(minutes: 10),
            ),
        _apiBaseUrl = apiBaseUrl,
        _useDirectProviders = useDirectProviders ??
            (kDebugMode ||
                const bool.fromEnvironment('TWISTAWAY_DIRECT_MAP_SERVICES'));

  final http.Client _client;
  final String _apiBaseUrl;
  final bool _useDirectProviders;
  final ExpiringLruCache<String, List<PlaceResult>> _cache;
  final Map<String, Future<List<PlaceResult>>> _inFlight = {};

  Future<List<PlaceResult>> search(String query,
      {SearchContext? context}) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) {
      return const [];
    }

    final queryParameters = {
      'q': trimmed,
      ...?context?.toQueryParameters(),
    };
    final cacheKey = _cacheKey(queryParameters);
    final cached = _cache.get(cacheKey);
    if (cached != null) {
      return cached;
    }

    final existing = _inFlight[cacheKey];
    if (existing != null) {
      return existing;
    }

    final request = _fetchPlaces(queryParameters, cacheKey);
    _inFlight[cacheKey] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<List<PlaceResult>> _fetchPlaces(
    Map<String, String> queryParameters,
    String cacheKey,
  ) async {
    if (_useDirectProviders) {
      return _fetchPhotonPlaces(queryParameters, cacheKey);
    }
    final response = await _client
        .get(
          Uri.parse('$_apiBaseUrl/integrations/search').replace(
            queryParameters: queryParameters,
          ),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw Exception('Location search failed (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final results = decoded['results'] as List<dynamic>? ?? const [];
    final places = results.map((item) {
      final value = item as Map<String, dynamic>;
      return PlaceResult(
        name: value['name'] as String? ?? 'Unknown place',
        latLng: LatLng(
          (value['latitude'] as num).toDouble(),
          (value['longitude'] as num).toDouble(),
        ),
        type: value['type'] as String?,
        distanceMeters: (value['distanceMeters'] as num?)?.toDouble(),
      );
    }).toList(growable: false);
    _cache.put(cacheKey, places);
    return places;
  }

  Future<List<PlaceResult>> _fetchPhotonPlaces(
    Map<String, String> queryParameters,
    String cacheKey,
  ) async {
    final centerLat = double.tryParse(queryParameters['centerLat'] ?? '');
    final centerLng = double.tryParse(queryParameters['centerLng'] ?? '');
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': queryParameters['q']!,
      'limit': '8',
      'lang': 'en',
      if (centerLat != null) 'lat': '$centerLat',
      if (centerLng != null) 'lon': '$centerLng',
    });
    final response = await _client.get(
      uri,
      headers: const {
        'User-Agent': 'Twistaway/0.1 (development contact: twistaway.local)',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw Exception('Location search failed (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final features = decoded['features'] as List<dynamic>? ?? const [];
    final distance = const Distance();
    final places = features
        .map((item) {
          final feature = item as Map<String, dynamic>;
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          final coordinates = geometry?['coordinates'] as List<dynamic>?;
          final properties =
              feature['properties'] as Map<String, dynamic>? ?? const {};
          if (coordinates == null || coordinates.length < 2) {
            return null;
          }
          final point = LatLng(
            (coordinates[1] as num).toDouble(),
            (coordinates[0] as num).toDouble(),
          );
          return PlaceResult(
            name: _photonDisplayName(properties),
            latLng: point,
            type: properties['osm_value'] as String?,
            distanceMeters: centerLat == null || centerLng == null
                ? null
                : distance.as(
                    LengthUnit.Meter,
                    LatLng(centerLat, centerLng),
                    point,
                  ),
          );
        })
        .whereType<PlaceResult>()
        .toList(growable: false)
      ..sort((a, b) => (a.distanceMeters ?? double.infinity)
          .compareTo(b.distanceMeters ?? double.infinity));
    final limited = places.take(6).toList(growable: false);
    _cache.put(cacheKey, limited);
    return limited;
  }

  String _photonDisplayName(Map<String, dynamic> properties) {
    final name = properties['name'] as String?;
    final houseNumber = properties['housenumber'] as String?;
    final street = properties['street'] as String?;
    final city = properties['city'] as String?;
    final state = properties['state'] as String?;
    final country = properties['country'] as String?;
    final addressLine = [houseNumber, street]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join(' ');
    final parts = <String>[
      if (name != null && name.isNotEmpty)
        name
      else if (addressLine.isNotEmpty)
        addressLine,
      if (city != null && city.isNotEmpty) city,
      if (state != null && state.isNotEmpty) state,
      if (country != null && country.isNotEmpty) country,
    ];
    final displayName = parts.toSet().join(', ');
    return displayName.isEmpty ? 'Unknown place' : displayName;
  }

  String _cacheKey(Map<String, String> queryParameters) {
    final keys = queryParameters.keys.toList()..sort();
    return keys
        .map(
          (key) =>
              '$key=${key == 'q' ? queryParameters[key]!.toLowerCase() : queryParameters[key]}',
        )
        .join('&');
  }

  void close() => _client.close();
}
