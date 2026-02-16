import 'dart:math';
import '../models/route_point.dart';

/// Calculates bearing (compass direction) between GPS coordinates.
class BearingCalculator {
  /// Calculate the initial bearing from point A to point B.
  /// Returns bearing in degrees (0-360, where 0 = North, 90 = East).
  static double calculateBearing(RoutePoint from, RoutePoint to) {
    final lat1 = _toRadians(from.lat);
    final lat2 = _toRadians(to.lat);
    final dLng = _toRadians(to.lng - from.lng);

    final x = sin(dLng) * cos(lat2);
    final y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);

    final bearing = atan2(x, y);
    return (_toDegrees(bearing) + 360) % 360;
  }

  /// Calculate smoothed bearing using surrounding points for
  /// more natural camera movement.
  ///
  /// [windowSize] controls how many surrounding points to consider.
  static double calculateSmoothedBearing(
    List<RoutePoint> points,
    int currentIndex, {
    int windowSize = 3,
  }) {
    if (points.length < 2) return 0;

    final start = (currentIndex - windowSize).clamp(0, points.length - 2);
    final end = (currentIndex + windowSize).clamp(1, points.length - 1);

    // Average bearing over the window
    double sinSum = 0;
    double cosSum = 0;
    int count = 0;

    for (int i = start; i < end; i++) {
      final bearing = calculateBearing(points[i], points[i + 1]);
      final rad = _toRadians(bearing);
      sinSum += sin(rad);
      cosSum += cos(rad);
      count++;
    }

    if (count == 0) return 0;

    final avgBearing = atan2(sinSum / count, cosSum / count);
    return (_toDegrees(avgBearing) + 360) % 360;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
  static double _toDegrees(double radians) => radians * 180 / pi;
}
