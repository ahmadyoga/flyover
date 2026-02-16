import 'package:flutter/material.dart';
import '../../core/models/route_data.dart';
import '../../core/models/video_config.dart';


/// Strava-style stats overlay widget that renders on top of the map.
/// Shows activity name, pace, distance, and elevation based on config and data availability.
class StatsOverlayWidget extends StatelessWidget {
  final RouteData route;
  final VideoConfig config;

  const StatsOverlayWidget({
    super.key,
    required this.route,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    if (!config.showOverlay) return const SizedBox.shrink();

    // Build stats list based on config + data availability
    final stats = <_StatItem>[];

    if (config.showPace && route.hasPace) {
      stats.add(_StatItem(
        label: 'Pace',
        value: route.formattedPace,
        unit: '/km',
      ));
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
