import '../models/route_point.dart';

/// Implements the Ramer-Douglas-Peucker algorithm to simplify
/// a GPS route by reducing unnecessary points while preserving shape.
class RouteSimplifier {
  /// Simplify a list of route points using the RDP algorithm.
  ///
  /// [epsilon] controls the tolerance in meters — higher values
  /// produce more aggressive simplification.
  static List<RoutePoint> simplify(List<RoutePoint> points,
      {double epsilon = 5.0}) {
    if (points.length < 3) return List.from(points);

    // Find the point with max distance from the line between first and last
    double maxDistance = 0;
    int maxIndex = 0;

    final start = points.first;
    final end = points.last;

    for (int i = 1; i < points.length - 1; i++) {
      final distance = _perpendicularDistance(points[i], start, end);
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    // If max distance is greater than epsilon, recursively simplify
    if (maxDistance > epsilon) {
      final left = simplify(
        points.sublist(0, maxIndex + 1),
        epsilon: epsilon,
      );
      final right = simplify(
        points.sublist(maxIndex),
        epsilon: epsilon,
      );

      // Combine results (remove duplicate point at junction)
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      // All intermediate points are within epsilon — keep only endpoints
      return [start, end];
    }
  }

  /// Calculate perpendicular distance from a point to a line
  /// defined by two endpoints, using geographic coordinates.
  static double _perpendicularDistance(
      RoutePoint point, RoutePoint lineStart, RoutePoint lineEnd) {
    // Convert to simple Cartesian approximation for distance calc
    final dx = lineEnd.lng - lineStart.lng;
    final dy = lineEnd.lat - lineStart.lat;

    if (dx == 0 && dy == 0) {
      return point.distanceTo(lineStart);
    }

    // Project point onto line
    final t = ((point.lng - lineStart.lng) * dx +
            (point.lat - lineStart.lat) * dy) /
        (dx * dx + dy * dy);

    final clampedT = t.clamp(0.0, 1.0);

    final projectedPoint = RoutePoint(
      lat: lineStart.lat + clampedT * dy,
      lng: lineStart.lng + clampedT * dx,
    );

    return point.distanceTo(projectedPoint);
  }
}
