import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:twistaway_app/features/navigation/road_speed_limit_service.dart';

void main() {
  test('parses mph and default OSM km/h speed limits', () {
    expect(parseOsmMaxSpeed('35 mph'), 35);
    expect(parseOsmMaxSpeed('80'), closeTo(49.7097, 0.001));
    expect(parseOsmMaxSpeed('signals'), isNull);
  });

  test('warning begins at the configured amount over the road limit', () {
    expect(
      isSpeedWarning(speedMph: 64, speedLimitMph: 55, thresholdMph: 10),
      isFalse,
    );
    expect(
      isSpeedWarning(speedMph: 65, speedLimitMph: 55, thresholdMph: 10),
      isTrue,
    );
    expect(
      isSpeedWarning(speedMph: 80, speedLimitMph: null, thresholdMph: 10),
      isFalse,
    );
  });

  test('looks up and caches the mapped road speed limit', () async {
    var calls = 0;
    final service = RoadSpeedLimitService(
      client: MockClient((request) async {
        calls += 1;
        expect(request.url.host, 'overpass-api.de');
        return http.Response(
          '{"elements":[{"tags":{"highway":"primary","maxspeed":"45 mph"}}]}',
          200,
        );
      }),
    );

    const position = LatLng(40.768, -73.525);
    expect(await service.speedLimitMph(position), 45);
    expect(await service.speedLimitMph(position), 45);
    expect(calls, 1);
    service.close();
  });

  test('does not guess when nearby mapped roads have different limits',
      () async {
    final service = RoadSpeedLimitService(
      client: MockClient(
        (_) async => http.Response(
          '{"elements":['
          '{"tags":{"highway":"primary","maxspeed":"35 mph"}},'
          '{"tags":{"highway":"secondary","maxspeed":"45 mph"}}]}',
          200,
        ),
      ),
    );

    expect(
      await service.speedLimitMph(const LatLng(40.768, -73.525)),
      isNull,
    );
    service.close();
  });
}
