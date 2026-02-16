import 'dart:io';
import 'package:gpx/gpx.dart';
import '../../core/models/route_point.dart';
import '../../core/models/route_data.dart';
import 'package:uuid/uuid.dart';

/// Parses GPX files and converts them into internal RouteData models.
class GpxParserService {
  static const _uuid = Uuid();

  /// Parse a GPX file from the given file path.
  /// Returns a [RouteData] containing the parsed route points.
  Future<RouteData> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw GpxParseException('File not found: $filePath');
    }

    final contents = await file.readAsString();
    return parseString(contents, sourceFile: filePath);
  }

  /// Parse GPX content from a string.
  RouteData parseString(String gpxContent, {String? sourceFile}) {
    try {
      final gpx = GpxReader().fromString(gpxContent);
      final points = <RoutePoint>[];

      // Extract name from GPX metadata
      String name = gpx.metadata?.name ?? 'Untitled Route';

      // Extract points from tracks
      for (final track in gpx.trks) {
        if (name == 'Untitled Route' && track.name != null) {
          name = track.name!;
        }
        for (final segment in track.trksegs) {
          for (final wpt in segment.trkpts) {
            if (wpt.lat != null && wpt.lon != null) {
              points.add(RoutePoint(
                lat: wpt.lat!,
                lng: wpt.lon!,
                elevation: wpt.ele,
                timestamp: wpt.time,
              ));
            }
          }
        }
      }

      // Fallback: extract from routes if no tracks
      if (points.isEmpty) {
        for (final route in gpx.rtes) {
          if (name == 'Untitled Route' && route.name != null) {
            name = route.name!;
          }
          for (final wpt in route.rtepts) {
            if (wpt.lat != null && wpt.lon != null) {
              points.add(RoutePoint(
                lat: wpt.lat!,
                lng: wpt.lon!,
                elevation: wpt.ele,
                timestamp: wpt.time,
              ));
            }
          }
        }
      }

      if (points.isEmpty) {
        throw GpxParseException('No valid GPS points found in GPX file');
      }

      // Detect Strava pauses: mark points after a time gap > threshold
      _markPauseResumes(points);

      final distance = RouteData.calculateTotalDistance(points);
      final duration = RouteData.calculateTotalDuration(points);
      final movingDuration = RouteData.calculateMovingDuration(points);

      return RouteData(
        id: _uuid.v4(),
        name: name,
        points: points,
        totalDistanceMeters: distance,
        totalDuration: duration,
        movingDuration: movingDuration,
        startTime: points.first.timestamp,
        sourceFile: sourceFile,
      );
    } catch (e) {
      if (e is GpxParseException) rethrow;
      throw GpxParseException('Failed to parse GPX: $e');
    }
  }
}

/// Custom exception for GPX parsing errors.
class GpxParseException implements Exception {
  final String message;
  GpxParseException(this.message);

  @override
  String toString() => 'GpxParseException: $message';
}

/// Detect Strava pauses by finding time gaps > threshold between consecutive
/// trackpoints. The point immediately after the gap is rebuilt with
/// [RoutePoint.isPauseResume] set to `true`.
void _markPauseResumes(
  List<RoutePoint> points, {
  Duration threshold = const Duration(seconds: 15),
}) {
  for (int i = 1; i < points.length; i++) {
    final prev = points[i - 1].timestamp;
    final curr = points[i].timestamp;
    if (prev != null && curr != null) {
      if (curr.difference(prev) > threshold) {
        points[i] = RoutePoint(
          lat: points[i].lat,
          lng: points[i].lng,
          elevation: points[i].elevation,
          timestamp: points[i].timestamp,
          isPauseResume: true,
        );
      }
    }
  }
}
