import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../core/models/route_data.dart';
import '../../core/models/video_config.dart';
import '../../features/animation_engine/camera_animation_controller.dart';
import '../../features/map_render/map_render_widget.dart';
import '../../ui/theme/app_theme.dart';
import 'rendering_progress_screen.dart';

/// Screen where users customize video settings before rendering.
class VideoCustomizationScreen extends StatefulWidget {
  final RouteData route;
  final List<String> initialEndingImages;

  const VideoCustomizationScreen({
    super.key,
    required this.route,
    this.initialEndingImages = const [],
  });

  @override
  State<VideoCustomizationScreen> createState() =>
      _VideoCustomizationScreenState();
}

class _VideoCustomizationScreenState extends State<VideoCustomizationScreen> {
  late VideoConfig _config = widget.initialEndingImages.isEmpty
      ? const VideoConfig()
      : VideoConfig(endingImagePaths: widget.initialEndingImages);
  MapboxMap? _mapboxMap;

  // Preview animation
  CameraAnimationController? _previewController;
  bool _isPreviewing = false;
  double _previewProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      _buildMapPreview(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Aspect Ratio'),
                      const SizedBox(height: 8),
                      _buildAspectRatioSelector(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Map Style'),
                      const SizedBox(height: 8),
                      _buildMapStyleSelector(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Camera'),
                      const SizedBox(height: 8),
                      _buildCameraSettings(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Route Color'),
                      const SizedBox(height: 8),
                      _buildColorSelector(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Overlay'),
                      const SizedBox(height: 8),
                      _buildOverlaySettings(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Video Duration'),
                      const SizedBox(height: 8),
                      _buildDurationSlider(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Ending Images'),
                      const SizedBox(height: 8),
                      _buildEndingImages(),
                      const SizedBox(height: 32),
                      _buildGenerateButton(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.surfaceCard,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.route.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${widget.route.formattedDistance} • ${widget.route.points.length} points',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.surfaceElevated,
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            // Map
            MapRenderWidget(
              routePoints: widget.route.points,
              config: _config,
              onMapCreated: (map) {
                _mapboxMap = map;
              },
              interactive: true,
            ),

            // Preview progress bar at bottom
            if (_isPreviewing)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: _previewProgress,
                  minHeight: 3,
                  backgroundColor: Colors.black38,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppTheme.primaryColor,
                  ),
                ),
              ),

            // Play/Pause button overlay
            Positioned(
              right: 12,
              bottom: 12,
              child: GestureDetector(
                onTap: _togglePreview,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        _isPreviewing ? AppTheme.primaryColor : Colors.black54,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isPreviewing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _togglePreview() {
    if (_isPreviewing) {
      _stopPreview();
    } else {
      _startPreview();
    }
  }

  void _startPreview() {
    if (_mapboxMap == null) return;

    _previewController?.dispose();

    // Use a shorter preview — show a 10s preview at 15fps for smoothness
    const previewFps = 15;
    final previewDurationSeconds = _config.videoDurationSeconds.clamp(10, 30);
    final totalFrameCount = previewDurationSeconds * previewFps;

    _previewController = CameraAnimationController(
      routePoints: widget.route.points,
      cameraPitch: _config.cameraPitch,
      cameraZoom: _config.cameraZoom,
      fps: previewFps,
      totalFrameCount: totalFrameCount,
    );

    _previewController!.onFrame = (frame) {
      if (_mapboxMap == null || !mounted) return;

      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(frame.center.lng, frame.center.lat),
          ),
          bearing: frame.bearing,
          pitch: frame.pitch,
          zoom: frame.zoom,
        ),
        MapAnimationOptions(duration: 0),
      );

      if (mounted) {
        setState(() {
          _previewProgress = frame.progress;
        });
      }
    };

    _previewController!.onComplete = () {
      if (mounted) {
        setState(() {
          _isPreviewing = false;
          _previewProgress = 0.0;
        });
      }
    };

    setState(() => _isPreviewing = true);
    _previewController!.play();
  }

  void _stopPreview() {
    _previewController?.pause();
    setState(() {
      _isPreviewing = false;
      _previewProgress = 0.0;
    });
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildAspectRatioSelector() {
    return Row(
      children: VideoAspectRatio.values.map((ratio) {
        final isSelected = _config.aspectRatio == ratio;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: ratio != VideoAspectRatio.values.last ? 12 : 0,
            ),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _config = _config.copyWith(aspectRatio: ratio);
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryColor.withValues(alpha: 0.15)
                      : AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : AppTheme.surfaceElevated,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      ratio == VideoAspectRatio.portrait9x16
                          ? Icons.stay_current_portrait_rounded
                          : Icons.stay_current_landscape_rounded,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.textSecondary,
                      size: 28,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ratio.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? AppTheme.primaryColor
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMapStyleSelector() {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: MapStyle.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final style = MapStyle.values[index];
          final isSelected = _config.mapStyle == style;
          return GestureDetector(
            onTap: () {
              setState(() {
                _config = _config.copyWith(mapStyle: style);
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 90,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryColor.withValues(alpha: 0.15)
                    : AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.surfaceElevated,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getMapStyleIcon(style),
                    color: isSelected
                        ? AppTheme.primaryColor
                        : AppTheme.textSecondary,
                    size: 24,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    style.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverlaySettings() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _buildToggleRow(
            'Show Overlay',
            _config.showOverlay,
            (v) => setState(() => _config = _config.copyWith(showOverlay: v)),
            enabled: true,
          ),
          if (_config.showOverlay) ...[
            const Divider(color: AppTheme.surfaceElevated, height: 8),
            _buildToggleRow(
              'Activity Name',
              _config.showActivityName,
              (v) => setState(
                  () => _config = _config.copyWith(showActivityName: v)),
              enabled: true,
            ),
            const Divider(color: AppTheme.surfaceElevated, height: 8),
            _buildToggleRow(
              'Distance',
              _config.showDistance,
              (v) =>
                  setState(() => _config = _config.copyWith(showDistance: v)),
              enabled: true,
            ),
            const Divider(color: AppTheme.surfaceElevated, height: 8),
            _buildToggleRow(
              'Pace',
              _config.showPace,
              (v) => setState(() => _config = _config.copyWith(showPace: v)),
              enabled: widget.route.hasPace,
              disabledHint: 'No timing data in GPX',
            ),
            const Divider(color: AppTheme.surfaceElevated, height: 8),
            _buildToggleRow(
              'Elevation',
              _config.showElevation,
              (v) =>
                  setState(() => _config = _config.copyWith(showElevation: v)),
              enabled: widget.route.hasElevation,
              disabledHint: 'No elevation data in GPX',
            ),
            const Divider(color: AppTheme.surfaceElevated, height: 8),
            _buildToggleRow(
              'Speed',
              _config.showSpeed,
              (v) => setState(() => _config = _config.copyWith(showSpeed: v)),
              enabled: true,
            ),
            if (_config.showSpeed) ...[
              const Divider(color: AppTheme.surfaceElevated, height: 8),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Format',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    SegmentedButton<SpeedFormat>(
                      segments: const [
                        ButtonSegment(
                          value: SpeedFormat.kmh,
                          label: Text('km/h'),
                        ),
                        ButtonSegment(
                          value: SpeedFormat.minPerKm,
                          label: Text('min/km'),
                        ),
                      ],
                      selected: {_config.speedFormat},
                      onSelectionChanged: (v) => setState(
                        () => _config = _config.copyWith(speedFormat: v.first),
                      ),
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildToggleRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    required bool enabled,
    String? disabledHint,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: enabled
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              ),
              if (!enabled && disabledHint != null)
                Text(
                  disabledHint,
                  style: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
        Switch(
          value: enabled ? value : false,
          onChanged: enabled ? onChanged : null,
          activeColor: AppTheme.primaryColor,
        ),
      ],
    );
  }

  IconData _getMapStyleIcon(MapStyle style) {
    return switch (style) {
      MapStyle.standard => Icons.map_rounded,
      MapStyle.standardSatellite => Icons.satellite_rounded,
      MapStyle.streets => Icons.location_city_rounded,
      MapStyle.outdoors => Icons.landscape_rounded,
      MapStyle.light => Icons.light_mode_rounded,
      MapStyle.dark => Icons.dark_mode_rounded,
      MapStyle.satellite => Icons.satellite_alt_rounded,
      MapStyle.satelliteStreets => Icons.layers_rounded,
      MapStyle.navigationDay => Icons.navigation_rounded,
      MapStyle.navigationNight => Icons.nightlight_rounded,
    };
  }

  Widget _buildColorSelector() {
    final colors = [
      const Color(0xFF00E5FF),
      const Color(0xFFFF6D00),
      const Color(0xFF76FF03),
      const Color(0xFFFF1744),
      const Color(0xFFE040FB),
      const Color(0xFFFFEA00),
      const Color(0xFFFFFFFF),
    ];

    return Wrap(
      spacing: 10,
      children: colors.map((color) {
        final isSelected = _config.routeColor == color;
        return GestureDetector(
          onTap: () {
            setState(() {
              _config = _config.copyWith(routeColor: color);
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 3,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDurationSlider() {
    final duration = _config.videoDurationSeconds;
    final label = duration >= 60
        ? '${duration ~/ 60}m ${duration % 60 > 0 ? '${duration % 60}s' : ''}'
        : '${duration}s';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Duration',
                  style: TextStyle(color: AppTheme.textSecondary)),
              Text(
                label.trim(),
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          Slider(
            value: _config.videoDurationSeconds.toDouble(),
            min: 10,
            max: 120,
            divisions: 22,
            onChanged: (value) {
              setState(() {
                _config = _config.copyWith(videoDurationSeconds: value.round());
              });
            },
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('10s',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              Text('2min',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCameraSettings() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _buildSliderRow(
            'Pitch',
            _config.cameraPitch,
            20,
            80,
            '${_config.cameraPitch.round()}°',
            (v) => setState(() => _config = _config.copyWith(cameraPitch: v)),
          ),
          const Divider(color: AppTheme.surfaceElevated, height: 24),
          _buildSliderRow(
            'Zoom',
            _config.cameraZoom,
            12,
            18,
            _config.cameraZoom.toStringAsFixed(1),
            (v) => setState(() => _config = _config.copyWith(cameraZoom: v)),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow(
    String label,
    double value,
    double min,
    double max,
    String displayValue,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(label,
              style: const TextStyle(color: AppTheme.textSecondary)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            displayValue,
            style: const TextStyle(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () {
          _stopPreview();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RenderingProgressScreen(
                route: widget.route,
                config: _config,
              ),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.movie_creation_rounded, size: 22),
            SizedBox(width: 10),
            Text(
              'Generate Video',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndingImages() {
    final paths = _config.endingImagePaths;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (paths.isNotEmpty) ...[
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: paths.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _buildImageThumbnail(paths[i], i),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: paths.length >= 5 ? null : _pickEndingImages,
              icon: const Icon(Icons.add_photo_alternate_rounded, size: 20),
              label: Text(
                paths.isEmpty ? 'Add Images' : 'Add More (${paths.length}/5)',
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: paths.length >= 5
                      ? Colors.grey.shade700
                      : AppTheme.primaryColor,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageThumbnail(String path, int index) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(path),
            width: 80,
            height: 100,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 80,
              height: 100,
              color: Colors.grey.shade800,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () {
              final updated = List<String>.from(_config.endingImagePaths)
                ..removeAt(index);
              setState(
                () => _config = _config.copyWith(endingImagePaths: updated),
              );
            },
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickEndingImages() async {
    final remaining = 5 - _config.endingImagePaths.length;
    if (remaining <= 0) return;

    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      limit: remaining,
    );

    if (images.isNotEmpty) {
      final newPaths = images.take(remaining).map((f) => f.path).toList();
      final updated = [..._config.endingImagePaths, ...newPaths];
      setState(
        () => _config = _config.copyWith(endingImagePaths: updated),
      );
    }
  }

  @override
  void dispose() {
    _previewController?.dispose();
    super.dispose();
  }
}
