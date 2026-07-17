import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:twistaway_app/features/planner/place_history.dart';
import 'package:twistaway_app/features/planner/place_search_service.dart';

void main() {
  test('frequently used matching places appear before nearby history', () {
    final history = PlaceHistory();
    const frequent = PlaceResult(
      name: 'Farmingdale State College, New York',
      latLng: LatLng(40.752, -73.428),
      type: 'college',
    );
    const nearby = PlaceResult(
      name: 'Farmingdale College Annex, New York',
      latLng: LatLng(40.7001, -73.5001),
      type: 'college',
    );

    history.record(frequent, usedAt: DateTime(2026, 1, 1));
    history.record(frequent, usedAt: DateTime(2026, 1, 2));
    history.record(nearby, usedAt: DateTime(2026, 1, 3));

    final results = history.suggestions(
      'farming col',
      center: const LatLng(40.7, -73.5),
    );

    expect(results.map((result) => result.name), [frequent.name, nearby.name]);
    expect(results.first.distanceMeters, isNotNull);
  });

  test('place history survives encoding and ignores malformed data', () {
    final history = PlaceHistory()
      ..record(
        const PlaceResult(
          name: 'Jones Beach State Park, New York',
          latLng: LatLng(40.5963, -73.5085),
          type: 'park',
        ),
        usedAt: DateTime.utc(2026, 7, 16),
      );

    final restored = PlaceHistory.decode(history.encode());
    expect(restored.suggestions('jones').single.name,
        'Jones Beach State Park, New York');
    expect(PlaceHistory.decode('{broken').isEmpty, isTrue);
  });
}
