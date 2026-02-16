import 'route_point.dart';

class RouteData {
  final String id;
  final String name;
  final List<RoutePoint> points;
  final double totalDistanceMeters;
  final Duration? totalDuration;
  final DateTime? startTime;
  final String? sourceFile;

  const RouteData({
    required this.id,
    required this.name,
    required this.points,
    required this.totalDistanceMeters,
    this.totalDuration,
    this.startTime,
    this.sourceFile,
  });

  /// Calculate total distance from points
  static double calculateTotalDistance(List<RoutePoint> points) {
    double total = 0;
    for (int i = 1; i < points.length; i++) {
      total += points[i - 1].distanceTo(points[i]);
    }
    return total;
  }

  /// Calculate total elevation gain (sum of positive elevation changes)
  static double calculateElevationGain(List<RoutePoint> points) {
    double gain = 0;
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1].elevation;
      final curr = points[i].elevation;
      if (prev != null && curr != null && curr > prev) {
        gain += curr - prev;
      }
    }
    return gain;
  }

  /// Calculate total duration from timestamps
  static Duration? calculateTotalDuration(List<RoutePoint> points) {
    if (points.isEmpty) return null;
    final first = points.first.timestamp;
    final last = points.last.timestamp;
    if (first == null || last == null) return null;
    return last.difference(first);
  }

  /// Get formatted distance string
  String get formattedDistance {
    if (totalDistanceMeters >= 1000) {
      return '${(totalDistanceMeters / 1000).toStringAsFixed(2)} km';
    }
    return '${totalDistanceMeters.toStringAsFixed(0)} m';
  }

  /// Get formatted duration string
  String get formattedDuration {
    if (totalDuration == null) return 'N/A';
    final hours = totalDuration!.inHours;
    final minutes = totalDuration!.inMinutes % 60;
    final seconds = totalDuration!.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m ${seconds}s';
  }

  /// Whether this route has elevation data
  bool get hasElevation =>
      points.any((p) => p.elevation != null);

  /// Whether this route has timing data (needed for pace)
  bool get hasPace =>
      totalDuration != null && totalDistanceMeters > 0;

  /// Total elevation gain in meters
  double get totalElevationGain => calculateElevationGain(points);

  /// Average pace in min/km (returns null if no timing data)
  double? get averagePaceMinPerKm {
    if (!hasPace) return null;
    final distKm = totalDistanceMeters / 1000;
    if (distKm <= 0) return null;
    return totalDuration!.inSeconds / 60 / distKm;
  }

  /// Formatted pace string (e.g. "6:52")
  String get formattedPace {
    final pace = averagePaceMinPerKm;
    if (pace == null) return 'N/A';
    final minutes = pace.floor();
    final seconds = ((pace - minutes) * 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Formatted elevation gain
  String get formattedElevationGain {
    final gain = totalElevationGain;
    return gain.round().toString();
  }

  /// Formatted distance as just the number + unit
  String get formattedDistanceShort {
    if (totalDistanceMeters >= 1000) {
      return (totalDistanceMeters / 1000).toStringAsFixed(1);
    }
    return totalDistanceMeters.toStringAsFixed(0);
  }

  /// Distance unit label
  String get distanceUnit => totalDistanceMeters >= 1000 ? 'km' : 'm';

  @override
  String toString() =>
      'RouteData(name: $name, points: ${points.length}, distance: $formattedDistance)';
}
