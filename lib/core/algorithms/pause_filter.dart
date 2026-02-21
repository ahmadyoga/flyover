import '../models/route_point.dart';

/// Calculates moving duration from GPS timestamps by detecting and
/// subtracting pause gaps. All lat/lng points are kept — only the
/// time accounting is adjusted.
class PauseFilter {
  /// Calculate the total moving duration by subtracting pause gaps.
  ///
  /// A pause is detected when consecutive points have a time gap
  /// >= [minPauseDuration]. The gap time is subtracted from the
  /// total elapsed time to get actual moving time.
  ///
  /// Returns null if points have no timestamps.
  static Duration? calculateMovingDuration(
    List<RoutePoint> points, {
    Duration minPauseDuration = const Duration(seconds: 30),
  }) {
    if (points.length < 2) return null;

    final first = points.first.timestamp;
    final last = points.last.timestamp;
    if (first == null || last == null) return null;

    final totalElapsed = last.difference(first);
    Duration totalPauseTime = Duration.zero;

    for (int i = 1; i < points.length; i++) {
      final prevTime = points[i - 1].timestamp;
      final currTime = points[i].timestamp;
      if (prevTime == null || currTime == null) continue;

      final gap = currTime.difference(prevTime);
      if (gap >= minPauseDuration) {
        totalPauseTime += gap;
      }
    }

    final movingTime = totalElapsed - totalPauseTime;
    return movingTime.isNegative ? Duration.zero : movingTime;
  }

  /// Count how many pause segments are in the route.
  static int countPauses(
    List<RoutePoint> points, {
    Duration minPauseDuration = const Duration(seconds: 30),
  }) {
    int pauses = 0;

    for (int i = 1; i < points.length; i++) {
      final prevTime = points[i - 1].timestamp;
      final currTime = points[i].timestamp;
      if (prevTime == null || currTime == null) continue;

      final gap = currTime.difference(prevTime);
      if (gap >= minPauseDuration) {
        pauses++;
      }
    }

    return pauses;
  }
}
