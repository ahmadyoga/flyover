import 'dart:convert';
import 'dart:io' as io;
import 'package:http/http.dart' as http;
import '../../core/models/route_data.dart';
import '../../core/models/route_point.dart';
import 'strava_auth_service.dart';
import 'strava_models.dart';

/// Client for the Strava API v3.
///
/// Fetches activity details and GPS streams, then converts
/// them to the app's [RouteData] format with Strava's official stats.
class StravaApiService {
  static const _baseUrl = 'https://www.strava.com/api/v3';

  final StravaAuthService _authService;

  StravaApiService({StravaAuthService? authService})
      : _authService = authService ?? StravaAuthService();

  /// Fetch activity summary (name, distance, moving_time, elevation, etc.)
  Future<StravaActivity> getActivity(int activityId) async {
    final token = await _authService.getAccessToken();
    final response = await http.get(
      Uri.parse('$_baseUrl/activities/$activityId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw StravaApiException(
        'Failed to fetch activity $activityId: ${response.statusCode}',
      );
    }

    return StravaActivity.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Fetch GPS streams (latlng, altitude, time) for an activity.
  Future<StravaStreams> getActivityStreams(int activityId) async {
    final token = await _authService.getAccessToken();
    final response = await http.get(
      Uri.parse(
        '$_baseUrl/activities/$activityId/streams'
        '?keys=latlng,altitude,time&key_by_type=true',
      ),
      headers: {'Authorization': 'Bearer $token'},
    );
    print('response');
    print(response.body);
    print('Authorization');
    print('Bearer $token');
    if (response.statusCode != 200) {
      throw StravaApiException(
        'Failed to fetch streams for activity $activityId: ${response.statusCode}',
      );
    }

    return StravaStreams.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Fetch a Strava activity and its GPS streams, then convert to [RouteData].
  ///
  /// Uses Strava's official distance and moving_time values rather than
  /// computing them from GPS points — this ensures parity with Strava's UI.
  Future<RouteData> fetchActivityAsRoute(int activityId) async {
    final activity = await getActivity(activityId);
    final streams = await getActivityStreams(activityId);

    if (streams.latlng.isEmpty) {
      throw StravaApiException('Activity $activityId has no GPS data.');
    }

    // Build RoutePoint list from streams
    final points = <RoutePoint>[];
    for (int i = 0; i < streams.latlng.length; i++) {
      final coords = streams.latlng[i];
      final altitude = i < streams.altitude.length ? streams.altitude[i] : 0.0;
      final timeOffset = i < streams.time.length ? streams.time[i] : 0;

      points.add(RoutePoint(
        lat: coords[0],
        lng: coords[1],
        elevation: altitude,
        timestamp: activity.startDate.add(Duration(seconds: timeOffset)),
      ));
    }

    return RouteData(
      id: 'strava_$activityId',
      name: activity.name,
      points: points,
      // Use Strava's official values for exact parity
      totalDistanceMeters: activity.distance,
      totalDuration: Duration(seconds: activity.elapsedTime),
      movingDuration: Duration(seconds: activity.movingTime),
      startTime: activity.startDate,
      sourceFile: 'strava://activities/$activityId',
    );
  }

  /// Parse a Strava activity ID from a URL string (synchronous).
  ///
  /// Handles direct URLs like `strava.com/activities/1234567890`.
  /// For short links like `strava.app.link/...`, use [resolveActivityId].
  static int? parseActivityId(String text) {
    final match = RegExp(r'strava\.com/activities/(\d+)').firstMatch(text);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Resolve a Strava activity ID from any Strava URL, including short links.
  ///
  /// Supports:
  /// - `https://strava.app.link/JQUQltdEN0b` (follows redirects)
  /// - `https://www.strava.com/activities/1234567890`

  static Future<int?> resolveActivityId(String url) async {
    // Try direct parse first
    final directId = parseActivityId(url);
    if (directId != null) return directId;

    // Only resolve strava.app.link short URLs
    if (!url.contains('strava.app.link')) return null;

    try {
      final client = io.HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      try {
        final request = await client.getUrl(Uri.parse(url.trim()));
        final response = await request.close();

        // Read the HTML body — Branch.io embeds the real URL in the page
        final body = await response.transform(io.systemEncoding.decoder).join();

        // Search the HTML for strava.com/activities/\d+
        final activityId = parseActivityId(body);
        if (activityId != null) return activityId;
      } finally {
        client.close();
      }
    } catch (e) {
      print('resolveActivityId error: $e');
    }

    return null;
  }
}

class StravaApiException implements Exception {
  final String message;
  const StravaApiException(this.message);

  @override
  String toString() => 'StravaApiException: $message';
}
