import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

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
    String apiBaseUrl = const String.fromEnvironment(
      'MOTOPLANNER_API_BASE_URL',
      defaultValue: 'http://localhost:4180',
    ),
  })  : _client = client ?? http.Client(),
        _apiBaseUrl = apiBaseUrl;

  final http.Client _client;
  final String _apiBaseUrl;
  final Map<String, List<PlaceResult>> _cache = {};
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
    final cached = _cache[cacheKey];
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
    if (_cache.length > 80) {
      _cache.remove(_cache.keys.first);
    }
    _cache[cacheKey] = places;
    return places;
  }

  String _cacheKey(Map<String, String> queryParameters) {
    final keys = queryParameters.keys.toList()..sort();
    return keys.map((key) => '$key=${queryParameters[key]}').join('&');
  }
}
