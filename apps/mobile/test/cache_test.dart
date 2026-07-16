import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:twistaway_app/core/cache/expiring_lru_cache.dart';
import 'package:twistaway_app/features/planner/place_search_service.dart';
import 'package:twistaway_app/features/planner/routing_service.dart';
import 'package:twistaway_app/features/planner/service_connection_mode.dart';

void main() {
  test('expiring LRU cache stays bounded and refreshes recent entries', () {
    var now = DateTime(2026);
    final cache = ExpiringLruCache<String, int>(
      maximumEntries: 2,
      timeToLive: const Duration(minutes: 5),
      clock: () => now,
    );

    cache.put('a', 1);
    cache.put('b', 2);
    expect(cache.get('a'), 1);
    cache.put('c', 3);

    expect(cache.get('b'), isNull);
    expect(cache.get('a'), 1);
    now = now.add(const Duration(minutes: 6));
    expect(cache.get('a'), isNull);
    expect(cache.length, 0);
  });

  test('place search reuses normalized cached results', () async {
    var requests = 0;
    Uri? requestedUri;
    final service = PlaceSearchService(
      client: MockClient((request) async {
        requests += 1;
        requestedUri = request.url;
        return http.Response(
          jsonEncode({
            'features': [
              {
                'geometry': {
                  'coordinates': [-73.525, 40.768],
                },
                'properties': {
                  'name': 'Hicksville',
                  'state': 'New York',
                  'osm_value': 'city',
                },
              },
            ],
          }),
          200,
        );
      }),
      useDirectProviders: true,
    );

    final first = await service.search('Hicksville');
    final second = await service.search('hicksville');

    expect(requests, 1);
    expect(requestedUri?.host, 'photon.komoot.io');
    expect(identical(first, second), isTrue);
    expect(first.single.name, 'Hicksville, New York');
    service.close();
  });

  test('routing reuses an identical planned route', () async {
    var requests = 0;
    Uri? requestedUri;
    final service = RoutingService(
      client: MockClient((request) async {
        requests += 1;
        requestedUri = request.url;
        return http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 1000,
                'duration': 120,
                'geometry': {
                  'coordinates': [
                    [-73.5, 40.7],
                    [-73.4, 40.8],
                  ],
                },
                'legs': [
                  {'steps': <Object>[]},
                ],
              },
            ],
          }),
          200,
        );
      }),
      useDirectProviders: true,
    );

    Future<PlannedRoute> plan() => service.route(
          origin: const LatLng(40.7, -73.5),
          destination: const LatLng(40.8, -73.4),
          preferences: const {'scenic': 0.5},
        );

    final first = await plan();
    final second = await plan();

    expect(requests, 1);
    expect(requestedUri?.host, 'router.project-osrm.org');
    expect(identical(first, second), isTrue);
    service.close();
  });

  test('automatic place search falls back when the API is unavailable',
      () async {
    final requestedHosts = <String>[];
    final service = PlaceSearchService(
      client: MockClient((request) async {
        requestedHosts.add(request.url.host);
        if (request.url.host == 'api.test') {
          return http.Response('{"error":"unavailable"}', 503);
        }
        return http.Response(
          jsonEncode({
            'features': [
              {
                'geometry': {
                  'coordinates': [-73.525, 40.768],
                },
                'properties': {
                  'name': 'Hicksville',
                  'state': 'New York',
                },
              },
            ],
          }),
          200,
        );
      }),
      apiBaseUrl: 'https://api.test',
      connectionMode: ServiceConnectionMode.automatic,
    );

    final results = await service.search('Hicksville');
    await service.search('Bethpage');

    expect(
      requestedHosts,
      ['api.test', 'photon.komoot.io', 'photon.komoot.io'],
    );
    expect(results.single.name, 'Hicksville, New York');
    service.close();
  });

  test('automatic routing falls back when the API is unavailable', () async {
    final requestedHosts = <String>[];
    final service = RoutingService(
      client: MockClient((request) async {
        requestedHosts.add(request.url.host);
        if (request.url.host == 'api.test') {
          return http.Response('{"error":"unavailable"}', 503);
        }
        return http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 1000,
                'duration': 120,
                'geometry': {
                  'coordinates': [
                    [-73.5, 40.7],
                    [-73.4, 40.8],
                  ],
                },
                'legs': [
                  {'steps': <Object>[]},
                ],
              },
            ],
          }),
          200,
        );
      }),
      apiBaseUrl: 'https://api.test',
      connectionMode: ServiceConnectionMode.automatic,
    );

    final route = await service.route(
      origin: const LatLng(40.7, -73.5),
      destination: const LatLng(40.8, -73.4),
      preferences: const {},
    );
    await service.route(
      origin: const LatLng(40.7, -73.5),
      destination: const LatLng(40.9, -73.3),
      preferences: const {},
    );

    expect(
      requestedHosts,
      ['api.test', 'router.project-osrm.org', 'router.project-osrm.org'],
    );
    expect(
      route.plannerNotes,
      contains('Twistaway API unavailable; used the direct routing provider.'),
    );
    service.close();
  });
}
