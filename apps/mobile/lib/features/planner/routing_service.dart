import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PlannedRoute {
  const PlannedRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
    this.plannerNotes = const [],
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteStep> steps;
  final List<String> plannerNotes;
}

class RouteStep {
  const RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final String instruction;
  final double distanceMeters;
  final double durationSeconds;
}

class RoutingService {
  RoutingService({
    http.Client? client,
    String apiBaseUrl = const String.fromEnvironment(
      'MOTOPLANNER_API_BASE_URL',
      defaultValue: 'http://localhost:4180',
    ),
  })  : _client = client ?? http.Client(),
        _apiBaseUrl = apiBaseUrl;

  final http.Client _client;
  final String _apiBaseUrl;

  Future<PlannedRoute> route({
    required LatLng origin,
    required LatLng destination,
    required Map<String, double> preferences,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl/integrations/route').replace(
      queryParameters: {
        'originLat': origin.latitude.toString(),
        'originLng': origin.longitude.toString(),
        'destinationLat': destination.latitude.toString(),
        'destinationLng': destination.longitude.toString(),
        for (final entry in preferences.entries) entry.key: entry.value.toString(),
      },
    );

    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      String detail = response.statusCode.toString();
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        detail = body['error'] as String? ?? detail;
      } catch (_) {
        detail = response.statusCode.toString();
      }
      throw Exception('Routing failed ($detail)');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['code'] != 'Ok') {
      throw Exception('Routing failed: ${decoded['code']}');
    }

    return _plannedRouteFromOsrm(decoded);
  }

  PlannedRoute _plannedRouteFromOsrm(Map<String, dynamic> decoded) {
    final route = (decoded['routes'] as List<dynamic>).first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coordinatesList = geometry['coordinates'] as List<dynamic>;
    final points = coordinatesList.map((coordinate) {
      final pair = coordinate as List<dynamic>;
      return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
    }).toList(growable: false);

    final legs = route['legs'] as List<dynamic>;
    final steps = legs.expand((leg) {
      final legMap = leg as Map<String, dynamic>;
      return (legMap['steps'] as List<dynamic>).map((stepValue) {
        final step = stepValue as Map<String, dynamic>;
        return RouteStep(
          instruction: _instructionFor(step),
          distanceMeters: (step['distance'] as num).toDouble(),
          durationSeconds: (step['duration'] as num).toDouble(),
        );
      });
    }).toList(growable: false);

    return PlannedRoute(
      points: points,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
      steps: steps,
      plannerNotes: _plannerNotes(decoded),
    );
  }

  Future<PlannedRoute> routeDirectForDiagnostics({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final coordinates = '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/driving/$coordinates',
      {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'true',
        'alternatives': 'false',
      },
    );

    final response = await _client.get(
      uri,
      headers: const {
        'User-Agent': 'MotoPlanner/0.1 (development contact: motoplanner.local)',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Routing failed (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['code'] != 'Ok') {
      throw Exception('Routing failed: ${decoded['code']}');
    }

    return _plannedRouteFromOsrm(decoded);
  }

  List<String> _plannerNotes(Map<String, dynamic> decoded) {
    final metadata = decoded['motoplanner'];
    if (metadata is! Map<String, dynamic>) {
      return const [];
    }
    final notes = metadata['notes'];
    if (notes is! List<dynamic>) {
      return const [];
    }
    return notes.map((note) => note.toString()).toList(growable: false);
  }

  String _instructionFor(Map<String, dynamic> step) {
    final explicitInstruction = step['instruction'] as String?;
    if (explicitInstruction != null && explicitInstruction.isNotEmpty) {
      return explicitInstruction;
    }

    final maneuver = step['maneuver'] as Map<String, dynamic>;
    final type = (maneuver['type'] as String? ?? 'continue').replaceAll('_', ' ');
    final modifier = maneuver['modifier'] as String?;
    final roadName = step['name'] as String? ?? '';

    final direction = modifier == null ? type : '$type $modifier';
    if (roadName.isEmpty) {
      return _sentence(direction);
    }
    return '${_sentence(direction)} onto $roadName';
  }

  String _sentence(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1);
  }
}
