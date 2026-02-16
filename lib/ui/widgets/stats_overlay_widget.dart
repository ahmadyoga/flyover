import 'package:flutter/material.dart';
import '../../core/models/route_data.dart';
import '../../core/models/route_point.dart';
import '../../core/models/video_config.dart';

/// Strava-style stats overlay widget that renders on top of the map.
/// Supports two modes:
///   1. Static mode — shows total pace, distance, elevation (for previews)
///   2. Dynamic mode — shows live speed, distance covered, current elevation
///      (when [currentFrameIndex] and [interpolatedPoints] are provided)
class StatsOverlayWidget extends StatelessWidget {
  final RouteData route;
  final VideoConfig config;

  /// For dynamic mode: index into [interpolatedPoints] for the current frame.
  final int? currentFrameIndex;

  /// For dynamic mode: the full list of interpolated points from the animation.
  final List<RoutePoint>? interpolatedPoints;

  /// Frames per second — used to derive current speed.
  final int? fps;

  const StatsOverlayWidget({
    super.key,
    required this.route,
    required this.config,
    this.currentFrameIndex,
    this.interpolatedPoints,
    this.fps,
  });

  bool get _isDynamic =>
      currentFrameIndex != null && interpolatedPoints != null;

  @override
  Widget build(BuildContext context) {
    if (!config.showOverlay) return const SizedBox.shrink();

    final stats = _isDynamic ? _buildDynamicStats() : _buildStaticStats();

    if (stats.isEmpty && !config.showActivityName) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xCC000000),
              Color(0x80000000),
              Color(0x00000000),
            ],
            stops: [0.0, 0.65, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Activity name
            if (config.showActivityName) ...[
              Text(
                route.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
            ],

            // Stats row
            if (stats.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: stats.map((stat) => _buildStatColumn(stat)).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Static mode (preview / no animation index)
  // ---------------------------------------------------------------------------
  List<_StatItem> _buildStaticStats() {
    final stats = <_StatItem>[];

    if (config.showPace && route.hasPace) {
      if (config.speedFormat == SpeedFormat.minPerKm) {
        stats.add(_StatItem(
          label: 'Pace',
          value: route.formattedPace,
          unit: '/km',
        ));
      } else {
        // Convert pace to km/h
        final paceMinPerKm = route.averagePaceMinPerKm;
        if (paceMinPerKm != null && paceMinPerKm > 0) {
          final kmh = 60.0 / paceMinPerKm;
          stats.add(_StatItem(
            label: 'Speed',
            value: kmh.toStringAsFixed(1),
            unit: 'km/h',
          ));
        }
      }
    }

    if (config.showDistance) {
      stats.add(_StatItem(
        label: 'Jarak',
        value: route.formattedDistanceShort,
        unit: route.distanceUnit,
      ));
    }

    if (config.showElevation && route.hasElevation) {
      stats.add(_StatItem(
        label: 'Elevasi',
        value: route.formattedElevationGain,
        unit: 'm',
      ));
    }

    return stats;
  }

  // ---------------------------------------------------------------------------
  // Dynamic mode (during frame capture)
  // ---------------------------------------------------------------------------
  List<_StatItem> _buildDynamicStats() {
    final stats = <_StatItem>[];
    final points = interpolatedPoints!;
    final idx = currentFrameIndex!.clamp(0, points.length - 1);

    // Current speed (km/h) — derived from real GPS timestamps
    if (config.showSpeed && idx > 0) {
      final speedKmh = _calculateSmoothedSpeed(points, idx);
      if (speedKmh != null) {
        if (config.speedFormat == SpeedFormat.minPerKm) {
          // Convert km/h to min/km
          if (speedKmh > 0.5) {
            final paceMinPerKm = 60.0 / speedKmh;
            final mins = paceMinPerKm.floor();
            final secs = ((paceMinPerKm - mins) * 60).round();
            stats.add(_StatItem(
              label: 'Pace',
              value: '$mins:${secs.toString().padLeft(2, '0')}',
              unit: '/km',
            ));
          }
        } else {
          stats.add(_StatItem(
            label: 'Kecepatan',
            value: speedKmh.toStringAsFixed(1),
            unit: 'km/h',
          ));
        }
      }
    }

    // Distance covered so far
    if (config.showDistance) {
      double distCovered = 0;
      for (int i = 1; i <= idx; i++) {
        distCovered += points[i - 1].distanceTo(points[i]);
      }
      if (distCovered >= 1000) {
        stats.add(_StatItem(
          label: 'Jarak',
          value: (distCovered / 1000).toStringAsFixed(1),
          unit: 'km',
        ));
      } else {
        stats.add(_StatItem(
          label: 'Jarak',
          value: distCovered.toStringAsFixed(0),
          unit: 'm',
        ));
      }
    }

    // Cumulative elevation gain (sum of positive elevation changes so far)
    if (config.showElevation && route.hasElevation) {
      double elevGain = 0;
      for (int i = 1; i <= idx; i++) {
        final prev = points[i - 1].elevation;
        final curr = points[i].elevation;
        if (prev != null && curr != null && curr > prev) {
          elevGain += curr - prev;
        }
      }
      stats.add(_StatItem(
        label: 'Elevasi',
        value: elevGain.round().toString(),
        unit: 'm',
      ));
    }

    return stats;
  }

  /// Calculate smoothed speed (km/h) using real GPS timestamps.
  /// Uses a sliding window of ±[windowSize] points for stable values.
  /// Skips over Strava pause boundaries to avoid near-zero speed readings.
  /// Returns null if timestamps are not available.
  double? _calculateSmoothedSpeed(List<RoutePoint> points, int idx) {
    const windowSize = 10;

    var startIdx = (idx - windowSize).clamp(0, points.length - 1);
    var endIdx = (idx + windowSize).clamp(0, points.length - 1);

    // Shrink window to avoid crossing pause boundaries.
    // Walk startIdx forward if there's a pause-resume between startIdx and idx.
    for (int i = startIdx + 1; i <= idx; i++) {
      if (points[i].isPauseResume) {
        startIdx = i; // start from after the pause
      }
    }
    // Walk endIdx backward if there's a pause-resume between idx+1 and endIdx.
    for (int i = idx + 1; i <= endIdx; i++) {
      if (points[i].isPauseResume) {
        endIdx = i - 1; // stop before the pause
        break;
      }
    }

    if (endIdx <= startIdx) return null;

    final startPt = points[startIdx];
    final endPt = points[endIdx];

    // Use real GPS timestamps if available
    if (startPt.timestamp != null && endPt.timestamp != null) {
      final timeDiffSeconds =
          endPt.timestamp!.difference(startPt.timestamp!).inMilliseconds /
              1000.0;
      if (timeDiffSeconds <= 0) return null;

      double dist = 0;
      for (int i = startIdx + 1; i <= endIdx; i++) {
        dist += points[i - 1].distanceTo(points[i]);
      }

      final speedMs = dist / timeDiffSeconds; // m/s
      return speedMs * 3.6; // km/h
    }

    // Fallback: use average pace from total route data
    if (route.hasPace) {
      final paceMinPerKm = route.averagePaceMinPerKm;
      if (paceMinPerKm != null && paceMinPerKm > 0) {
        return 60.0 / paceMinPerKm; // convert min/km → km/h
      }
    }

    return null;
  }

  Widget _buildStatColumn(_StatItem stat) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          stat.label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              stat.value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              stat.unit,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  final String unit;

  const _StatItem({
    required this.label,
    required this.value,
    required this.unit,
  });
}
