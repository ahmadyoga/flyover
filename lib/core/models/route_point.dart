import 'dart:math';

class RoutePoint {
  final double lat;
  final double lng;
  final double? elevation;
  final DateTime? timestamp;

  /// True if this point is immediately after a Strava pause/resume.
  /// Used to skip pause gaps in speed calculations.
  final bool isPauseResume;

  const RoutePoint({
    required this.lat,
    required this.lng,
    this.elevation,
    this.timestamp,
    this.isPauseResume = false,
  });

  /// Calculate distance in meters to another point using Haversine formula
  double distanceTo(RoutePoint other) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(other.lat - lat);
    final dLng = _toRadians(other.lng - lng);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat)) *
            cos(_toRadians(other.lat)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  /// Linear interpolation between this point and another
  RoutePoint lerp(RoutePoint other, double t) {
    return RoutePoint(
      lat: lat + (other.lat - lat) * t,
      lng: lng + (other.lng - lng) * t,
      elevation: (elevation != null && other.elevation != null)
          ? elevation! + (other.elevation! - elevation!) * t
          : elevation ?? other.elevation,
      timestamp: (timestamp != null && other.timestamp != null)
          ? DateTime.fromMillisecondsSinceEpoch(
              (timestamp!.millisecondsSinceEpoch +
                      (other.timestamp!.millisecondsSinceEpoch -
                              timestamp!.millisecondsSinceEpoch) *
                          t)
                  .round(),
            )
          : null,
      // Propagate pause flag — interpolated points between a normal point
      // and a pause-resume point inherit the flag.
      isPauseResume: other.isPauseResume,
    );
  }

  static double _toRadians(double degrees) => degrees * pi / 180;

  @override
  String toString() => 'RoutePoint(lat: $lat, lng: $lng, elev: $elevation)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoutePoint &&
          runtimeType == other.runtimeType &&
          lat == other.lat &&
          lng == other.lng;

  @override
  int get hashCode => lat.hashCode ^ lng.hashCode;
}
