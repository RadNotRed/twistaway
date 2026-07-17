import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

class NavigationMotionSmoother {
  NavigationMotionSmoother({
    this.correctionDuration = const Duration(milliseconds: 700),
    this.maximumPrediction = const Duration(milliseconds: 2500),
    this.maximumPredictionMeters = 35,
  });

  final Duration correctionDuration;
  final Duration maximumPrediction;
  final double maximumPredictionMeters;

  LatLng? _from;
  LatLng? _target;
  DateTime? _anchorTime;
  double _speedMetersPerSecond = 0;
  double _headingDegrees = 0;

  void reset({
    required LatLng from,
    required LatLng target,
    required DateTime at,
    required double speedMetersPerSecond,
    required double headingDegrees,
  }) {
    _from = from;
    _target = target;
    _anchorTime = at;
    _speedMetersPerSecond =
        speedMetersPerSecond.isFinite ? math.max(0, speedMetersPerSecond) : 0;
    _headingDegrees = headingDegrees;
  }

  void clear() {
    _from = null;
    _target = null;
    _anchorTime = null;
  }

  LatLng? positionAt(DateTime now) {
    final from = _from;
    final target = _target;
    final anchorTime = _anchorTime;
    if (from == null || target == null || anchorTime == null) return null;

    final elapsed = now.difference(anchorTime);
    final predictionTime = elapsed.isNegative
        ? Duration.zero
        : elapsed > maximumPrediction
            ? maximumPrediction
            : elapsed;
    final canPredict = _speedMetersPerSecond >= 1 &&
        _headingDegrees.isFinite &&
        _headingDegrees >= 0 &&
        _headingDegrees < 360;
    final predictedTarget = canPredict
        ? destinationPoint(
            target,
            math.min(
              maximumPredictionMeters,
              _speedMetersPerSecond *
                  predictionTime.inMicroseconds /
                  Duration.microsecondsPerSecond,
            ),
            _headingDegrees,
          )
        : target;
    final correctionProgress = correctionDuration == Duration.zero
        ? 1.0
        : (elapsed.inMicroseconds / correctionDuration.inMicroseconds)
            .clamp(0.0, 1.0);
    final eased = 1 - math.pow(1 - correctionProgress, 3).toDouble();
    return LatLng(
      from.latitude + (predictedTarget.latitude - from.latitude) * eased,
      from.longitude + (predictedTarget.longitude - from.longitude) * eased,
    );
  }
}

LatLng destinationPoint(
  LatLng start,
  double distanceMeters,
  double bearingDegrees,
) {
  const earthRadiusMeters = 6371000.0;
  final angularDistance = distanceMeters / earthRadiusMeters;
  final bearing = bearingDegrees * math.pi / 180;
  final latitude = start.latitude * math.pi / 180;
  final longitude = start.longitude * math.pi / 180;
  final destinationLatitude = math.asin(
    math.sin(latitude) * math.cos(angularDistance) +
        math.cos(latitude) * math.sin(angularDistance) * math.cos(bearing),
  );
  final destinationLongitude = longitude +
      math.atan2(
        math.sin(bearing) * math.sin(angularDistance) * math.cos(latitude),
        math.cos(angularDistance) -
            math.sin(latitude) * math.sin(destinationLatitude),
      );
  return LatLng(
    destinationLatitude * 180 / math.pi,
    ((destinationLongitude * 180 / math.pi + 540) % 360) - 180,
  );
}
