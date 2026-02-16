import '../models/route_point.dart';

/// Generates evenly-spaced interpolated points along a route
/// for smooth camera animation at a target FPS.
class RouteInterpolator {
  /// Interpolate route to produce evenly-spaced points.
  ///
  /// [targetSpacingMeters] — desired distance between consecutive points.
  /// Lower values = smoother animation but more frames.
  static List<RoutePoint> interpolate(
    List<RoutePoint> points, {
    double targetSpacingMeters = 5.0,
  }) {
    if (points.length < 2) return List.from(points);

    final result = <RoutePoint>[points.first];

    double accumulated = 0;

    for (int i = 0; i < points.length - 1; i++) {
      final segmentDistance = points[i].distanceTo(points[i + 1]);
      double segmentOffset = 0;

      // Handle remaining distance from previous segment
      if (accumulated > 0) {
        final needed = targetSpacingMeters - accumulated;
        if (needed <= segmentDistance) {
          segmentOffset = needed;
          final t = segmentOffset / segmentDistance;
          result.add(points[i].lerp(points[i + 1], t));
          accumulated = 0;
        } else {
          accumulated += segmentDistance;
          continue;
        }
      }

      // Place remaining points at regular intervals in this segment
      while (segmentOffset + targetSpacingMeters <= segmentDistance) {
        segmentOffset += targetSpacingMeters;
        final t = segmentOffset / segmentDistance;
        result.add(points[i].lerp(points[i + 1], t));
      }

      // Track remaining distance
      accumulated = segmentDistance - segmentOffset;
    }

    // Always include the last point
    if (result.last != points.last) {
      result.add(points.last);
    }

    return result;
  }

  /// Interpolate to achieve a target number of total points.
  static List<RoutePoint> interpolateToCount(
    List<RoutePoint> points, {
    required int targetCount,
  }) {
    if (points.length < 2 || targetCount < 2) return List.from(points);

    // Calculate total distance
    double totalDist = 0;
    for (int i = 0; i < points.length - 1; i++) {
      totalDist += points[i].distanceTo(points[i + 1]);
    }

    final spacing = totalDist / (targetCount - 1);
    return interpolate(points, targetSpacingMeters: spacing);
  }

  /// Calculate the total route distance in meters.
  static double totalDistance(List<RoutePoint> points) {
    double total = 0;
    for (int i = 0; i < points.length - 1; i++) {
      total += points[i].distanceTo(points[i + 1]);
    }
    return total;
  }
}
