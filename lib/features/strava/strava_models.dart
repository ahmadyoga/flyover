// Data models for Strava API responses.

class StravaActivity {
  final int id;
  final String name;
  final String type;
  final double distance; // meters
  final int movingTime; // seconds
  final int elapsedTime; // seconds
  final double totalElevationGain; // meters
  final DateTime startDate;

  const StravaActivity({
    required this.id,
    required this.name,
    required this.type,
    required this.distance,
    required this.movingTime,
    required this.elapsedTime,
    required this.totalElevationGain,
    required this.startDate,
  });

  factory StravaActivity.fromJson(Map<String, dynamic> json) {
    return StravaActivity(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Strava Activity',
      type: json['type'] as String? ?? 'Run',
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      movingTime: json['moving_time'] as int? ?? 0,
      elapsedTime: json['elapsed_time'] as int? ?? 0,
      totalElevationGain:
          (json['total_elevation_gain'] as num?)?.toDouble() ?? 0.0,
      startDate: DateTime.parse(
          json['start_date'] as String? ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Parsed GPS stream data from Strava's activity streams endpoint.
class StravaStreams {
  /// List of [lat, lng] pairs.
  final List<List<double>> latlng;

  /// Altitude in meters for each point.
  final List<double> altitude;

  /// Time offset in seconds from activity start for each point.
  final List<int> time;

  const StravaStreams({
    required this.latlng,
    required this.altitude,
    required this.time,
  });

  factory StravaStreams.fromJson(Map<String, dynamic> json) {
    List<List<double>> latlng = [];
    List<double> altitude = [];
    List<int> time = [];

    // Parse latlng stream
    final latlngData = json['latlng']?['data'] as List<dynamic>?;
    if (latlngData != null) {
      latlng = latlngData
          .map((e) =>
              (e as List<dynamic>).map((v) => (v as num).toDouble()).toList())
          .toList();
    }

    // Parse altitude stream
    final altitudeData = json['altitude']?['data'] as List<dynamic>?;
    if (altitudeData != null) {
      altitude = altitudeData.map((e) => (e as num).toDouble()).toList();
    }

    // Parse time stream
    final timeData = json['time']?['data'] as List<dynamic>?;
    if (timeData != null) {
      time = timeData.map((e) => (e as num).toInt()).toList();
    }

    return StravaStreams(latlng: latlng, altitude: altitude, time: time);
  }
}
