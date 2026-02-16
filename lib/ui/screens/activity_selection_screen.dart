import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../features/gpx_import/gpx_import_bloc.dart';
import '../../features/strava/strava_auth_service.dart';
import '../../core/models/route_data.dart';
import '../../ui/theme/app_theme.dart';
import 'video_customization_screen.dart';
import 'package:intl/intl.dart';

/// Screen showing imported GPX activities.
/// Users can import new GPX files and select activities for video generation.
class ActivitySelectionScreen extends StatelessWidget {
  const ActivitySelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<GpxImportBloc, GpxImportState>(
      listenWhen: (prev, curr) =>
          curr.pendingSharedImagePath != null &&
          prev.pendingSharedImagePath != curr.pendingSharedImagePath,
      listener: (context, state) {
        // Auto-navigate when Strava import with shared image completes
        final imagePath = state.pendingSharedImagePath;
        final route = state.routes.lastOrNull;
        if (imagePath != null && route != null) {
          context.read<GpxImportBloc>().add(ClearPendingSharedImage());
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BlocProvider.value(
                value: context.read<GpxImportBloc>(),
                child: VideoCustomizationScreen(
                  route: route,
                  initialEndingImages: [imagePath],
                ),
              ),
            ),
          );
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                Expanded(
                  child: BlocConsumer<GpxImportBloc, GpxImportState>(
                    listener: (context, state) {
                      if (state.error != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: AppTheme.errorColor),
                                const SizedBox(width: 12),
                                Expanded(child: Text(state.error!)),
                              ],
                            ),
                          ),
                        );
                      }
                    },
                    builder: (context, state) {
                      if (state.isLoading) {
                        return const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Importing activity...',
                                  style:
                                      TextStyle(color: AppTheme.textSecondary)),
                            ],
                          ),
                        );
                      }

                      if (state.routes.isEmpty) {
                        return _buildEmptyState(context);
                      }

                      return _buildRouteList(context, state.routes);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: _buildFAB(context),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShaderMask(
            shaderCallback: (bounds) =>
                AppTheme.primaryGradient.createShader(bounds),
            child: const Text(
              'Flyover',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Create cinematic flyover videos from your activities',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.surfaceElevated, height: 1),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final stravaAuth = StravaAuthService();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(
                Icons.route_rounded,
                size: 64,
                color: AppTheme.primaryColor.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Activities Yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Import a GPX file or share\nan activity from Strava',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                context.read<GpxImportBloc>().add(PickGpxFile());
              },
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Import GPX File'),
            ),
            const SizedBox(height: 12),
            FutureBuilder<bool>(
              future: stravaAuth.isAuthenticated,
              builder: (context, snapshot) {
                final isConnected = snapshot.data ?? false;
                if (isConnected) {
                  return const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 16, color: AppTheme.successColor),
                      SizedBox(width: 6),
                      Text(
                        'Strava connected — share an activity from Strava',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  );
                }
                return OutlinedButton.icon(
                  onPressed: stravaAuth.isConfigured
                      ? () => stravaAuth.authorize()
                      : null,
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: Text(
                    stravaAuth.isConfigured
                        ? 'Connect Strava'
                        : 'Strava not configured',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFC4C02),
                    side: const BorderSide(color: Color(0xFFFC4C02)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteList(BuildContext context, List<RouteData> routes) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: routes.length,
      itemBuilder: (context, index) {
        return _RouteCard(
          route: routes[index],
          index: index,
        );
      },
    );
  }

  Widget _buildFAB(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () {
        context.read<GpxImportBloc>().add(PickGpxFile());
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text('Import'),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final RouteData route;
  final int index;

  const _RouteCard({required this.route, required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BlocProvider.value(
                  value: context.read<GpxImportBloc>(),
                  child: VideoCustomizationScreen(route: route),
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.surfaceElevated,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Route icon with gradient background
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.terrain_rounded,
                    color: Colors.black,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                // Route info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        route.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _InfoChip(
                            icon: Icons.straighten_rounded,
                            label: route.formattedDistance,
                          ),
                          const SizedBox(width: 12),
                          _InfoChip(
                            icon: Icons.timer_rounded,
                            label: route.formattedDuration,
                          ),
                          if (route.startTime != null) ...[
                            const SizedBox(width: 12),
                            _InfoChip(
                              icon: Icons.calendar_today_rounded,
                              label:
                                  DateFormat('MMM d').format(route.startTime!),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Arrow
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.textSecondary.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}
