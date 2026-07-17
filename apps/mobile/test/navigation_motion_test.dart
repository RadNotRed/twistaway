import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:twistaway_app/features/navigation/navigation_motion_smoother.dart';

void main() {
  test('smoothly corrects a new GPS fix before predicting forward', () {
    final smoother = NavigationMotionSmoother(
      correctionDuration: const Duration(seconds: 1),
      maximumPrediction: const Duration(seconds: 2),
    );
    final now = DateTime(2026);
    const from = LatLng(40, -73);
    const target = LatLng(40.0001, -73);

    smoother.reset(
      from: from,
      target: target,
      at: now,
      speedMetersPerSecond: 10,
      headingDegrees: 0,
    );

    expect(smoother.positionAt(now), from);
    final halfway = smoother.positionAt(
      now.add(const Duration(milliseconds: 500)),
    )!;
    expect(halfway.latitude, greaterThan(from.latitude));
    expect(halfway.latitude, lessThan(40.0002));
    final predicted = smoother.positionAt(now.add(const Duration(seconds: 3)))!;
    expect(predicted.latitude, greaterThan(target.latitude));
  });

  test('does not dead reckon when speed or heading is unusable', () {
    final smoother = NavigationMotionSmoother(
      correctionDuration: Duration.zero,
    );
    final now = DateTime(2026);
    const point = LatLng(40, -73);
    smoother.reset(
      from: point,
      target: point,
      at: now,
      speedMetersPerSecond: 0,
      headingDegrees: -1,
    );

    expect(smoother.positionAt(now.add(const Duration(seconds: 2))), point);
  });
}
