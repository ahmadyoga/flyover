import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../core/models/route_data.dart';
import '../../core/models/video_config.dart';
import '../../features/animation_engine/camera_animation_controller.dart';
import '../../features/video_export/frame_capture_service.dart';
import '../../features/video_export/video_render_service.dart';
import '../../features/video_export/export_service.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/stats_overlay_widget.dart';

/// Screen showing the video rendering progress with frame capture
/// and native H.264 encoding status.
class RenderingProgressScreen extends StatefulWidget {
  final RouteData route;
  final VideoConfig config;

  const RenderingProgressScreen({
    super.key,
    required this.route,
    required this.config,
  });

  @override
  State<RenderingProgressScreen> createState() =>
      _RenderingProgressScreenState();
}

class _RenderingProgressScreenState extends State<RenderingProgressScreen>
    with TickerProviderStateMixin {
  late final CameraAnimationController _animController;
  final FrameCaptureService _captureService = FrameCaptureService();
  final VideoRenderService _renderService = VideoRenderService();
  final ExportService _exportService = ExportService();

  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _positionMarkerManager;

  // State
  _RenderPhase _phase = _RenderPhase.initializing;
  int _capturedFrames = 0;
  int _totalFrames = 0;
  int _currentFrameIndex = 0;
  String? _outputPath;
  String? _error;
  DateTime? _startTime;
  bool _isCancelled = false;

  /// Widget overlay for ending image slideshow (null = not showing).
  Widget? _endingImageOverlay;

  /// Number of intro/outro frames to capture for zoom transitions.
  static const int _zoomTransitionFrames = 60;

  // Animation
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    final totalFrameCount =
        widget.config.videoDurationSeconds * widget.config.fps;

    _animController = CameraAnimationController(
      routePoints: widget.route.points,
      cameraPitch: widget.config.cameraPitch,
      cameraZoom: widget.config.cameraZoom,
      fps: widget.config.fps,
      totalFrameCount: totalFrameCount,
    );

    _totalFrames = _animController.totalFrames +
        (widget.config.endingImagePaths.length * widget.config.fps * 3);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  Future<void> _startRendering() async {
    _startTime = DateTime.now();

    try {
      // Phase 1: Initialize encoder
      setState(() => _phase = _RenderPhase.initializing);
      _outputPath = await _renderService.setup(widget.config);

      if (_isCancelled) return;

      // Phase 2: Zoom-in intro (captured to video)
      setState(() => _phase = _RenderPhase.capturing);
      await _captureZoomInIntro();

      if (_isCancelled) return;

      // Phase 3: Capture and encode route frames
      await _captureAndEncodeFrames();

      if (_isCancelled) return;

      print('Phase 4: Zoom-out outro — reveal full trail and zoom to fit');
      // Phase 4: Zoom-out outro — reveal full trail and zoom to fit
      await _captureZoomOutOutro();

      if (_isCancelled) return;

      // Phase 5: Ending image slideshow (if images selected)
      if (widget.config.endingImagePaths.isNotEmpty) {
        await _captureEndingSlideshow();
      }

      if (_isCancelled) return;

      // Phase 5: Finalize
      setState(() => _phase = _RenderPhase.encoding);
      await _renderService.finish();

      if (_isCancelled) return;

      // Done!
      setState(() => _phase = _RenderPhase.complete);
    } catch (e) {
      if (mounted && !_isCancelled) {
        setState(() {
          _phase = _RenderPhase.error;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _captureAndEncodeFrames() async {
    for (int i = 0; i < _totalFrames && !_isCancelled; i++) {
      _animController.seekToFrame(i);
      final frame = _animController.getCurrentFrame();

      // Move camera
      if (_mapboxMap != null) {
        await _mapboxMap!.flyTo(
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

        // Update position marker dot
        await _updatePositionMarker(frame.center.lat, frame.center.lng);

        // Update progressive route trail (reveal from start to current)
        await _updateRouteTrail(i);

        // Wait for map render
        await Future.delayed(const Duration(milliseconds: 80));
      }

      // Capture RGBA at full resolution and append directly to encoder
      // pixelRatio compensates for the display scaling (widget is shown at 1/4 size)
      final pixelRatio = widget.config.aspectRatio.width.toDouble() /
          (widget.config.aspectRatio.width.toDouble() / 4);
      final rgbaData =
          await _captureService.captureFrame(pixelRatio: pixelRatio);
      if (rgbaData != null) {
        await _renderService.appendFrame(rgbaData);
      }

      if (mounted) {
        setState(() {
          _capturedFrames = i + 1;
          _currentFrameIndex = i;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Zoom-in intro: smoothly animate from overview to the start point
  // ---------------------------------------------------------------------------
  Future<void> _captureZoomInIntro() async {
    if (_mapboxMap == null || _isCancelled) return;

    _animController.seekToFrame(0);
    final firstFrame = _animController.getCurrentFrame();

    // Compute overview camera that fits the whole route
    final overviewCamera = await _getOverviewCamera();
    final overviewZoom = overviewCamera?.zoom ?? 12.0;

    // Extract overview center lat/lng
    final overviewCenterPt = overviewCamera?.center;
    final startLat = overviewCenterPt != null
        ? overviewCenterPt.coordinates.lat.toDouble()
        : firstFrame.center.lat;
    final startLng = overviewCenterPt != null
        ? overviewCenterPt.coordinates.lng.toDouble()
        : firstFrame.center.lng;

    final targetZoom = firstFrame.zoom;

    for (int i = 0; i < _zoomTransitionFrames && !_isCancelled; i++) {
      final t = i / (_zoomTransitionFrames - 1); // 0.0 → 1.0
      // Ease-in-out cubic
      final eased = t < 0.5
          ? 4 * t * t * t
          : 1 - (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) / 2;

      final interpZoom = overviewZoom + (targetZoom - overviewZoom) * eased;
      final interpPitch = firstFrame.pitch * eased;
      final interpLat = startLat + (firstFrame.center.lat - startLat) * eased;
      final interpLng = startLng + (firstFrame.center.lng - startLng) * eased;

      await _mapboxMap!.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(interpLng, interpLat)),
          zoom: interpZoom,
          pitch: interpPitch,
          bearing: firstFrame.bearing * eased,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // Capture frame
      final pixelRatio = widget.config.aspectRatio.width.toDouble() /
          (widget.config.aspectRatio.width.toDouble() / 4);
      final rgbaData =
          await _captureService.captureFrame(pixelRatio: pixelRatio);
      if (rgbaData != null) {
        await _renderService.appendFrame(rgbaData);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Zoom-out outro: reveal full trail and zoom to fit entire route
  // ---------------------------------------------------------------------------
  Future<void> _captureZoomOutOutro() async {
    if (_mapboxMap == null || _isCancelled) return;

    // Reveal the entire route trail
    await _updateRouteTrail(_animController.interpolatedPoints.length - 1);

    // Get current camera state (= last animation frame)
    final lastFrame = _animController.getCurrentFrame();

    // Compute overview camera that fits the whole route
    final overviewCamera = await _getOverviewCamera();
    final targetZoom = overviewCamera?.zoom ?? 12.0;

    final overviewCenterPt = overviewCamera?.center;
    final endLat = overviewCenterPt != null
        ? overviewCenterPt.coordinates.lat.toDouble()
        : lastFrame.center.lat;
    final endLng = overviewCenterPt != null
        ? overviewCenterPt.coordinates.lng.toDouble()
        : lastFrame.center.lng;

    for (int i = 0; i < _zoomTransitionFrames && !_isCancelled; i++) {
      final t = i / (_zoomTransitionFrames - 1); // 0.0 → 1.0
      // Ease-in-out cubic
      final eased = t < 0.5
          ? 4 * t * t * t
          : 1 - (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) / 2;

      final interpZoom = lastFrame.zoom + (targetZoom - lastFrame.zoom) * eased;
      final interpPitch = lastFrame.pitch + (0.0 - lastFrame.pitch) * eased;
      final interpBearing = lastFrame.bearing * (1 - eased);
      final interpLat =
          lastFrame.center.lat + (endLat - lastFrame.center.lat) * eased;
      final interpLng =
          lastFrame.center.lng + (endLng - lastFrame.center.lng) * eased;

      await _mapboxMap!.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(interpLng, interpLat)),
          zoom: interpZoom,
          pitch: interpPitch,
          bearing: interpBearing,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // Capture frame
      final pixelRatio = widget.config.aspectRatio.width.toDouble() /
          (widget.config.aspectRatio.width.toDouble() / 4);
      final rgbaData =
          await _captureService.captureFrame(pixelRatio: pixelRatio);
      if (rgbaData != null) {
        await _renderService.appendFrame(rgbaData);
      }
    }
    await Future.delayed(const Duration(seconds: 2));
  }

  /// Capture ending image slideshow — each image shown on a blurred map
  /// background for ~3 seconds with a subtle scale-up animation.
  Future<void> _captureEndingSlideshow() async {
    final imagePaths = widget.config.endingImagePaths;
    if (imagePaths.isEmpty) return;

    final framesPerImage = widget.config.fps * 3; // 3 seconds per image
    final pixelRatio = widget.config.aspectRatio.width.toDouble() /
        (widget.config.aspectRatio.width.toDouble() / 4);

    for (final imagePath in imagePaths) {
      if (_isCancelled) return;

      for (int frame = 0; frame < framesPerImage; frame++) {
        if (_isCancelled) return;

        // Scale from 0.95 → 1.0 with ease-out curve
        final t = frame / framesPerImage;
        final eased = 1.0 - (1.0 - t) * (1.0 - t); // ease-out quad
        final scale = 0.95 + 0.05 * eased;
        // Fade in over first 10 frames
        final opacity = (frame / 10).clamp(0.0, 1.0);

        setState(() {
          _endingImageOverlay = Positioned.fill(
            child: Opacity(
              opacity: opacity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Blur the map underneath
                  BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                  // The image with scale animation
                  Center(
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: widget.config.aspectRatio.width.toDouble() /
                              4 *
                              0.8,
                          maxHeight:
                              widget.config.aspectRatio.height.toDouble() /
                                  4 *
                                  0.7,
                        ),
                        child: Image.file(
                          File(imagePath),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final rgbaData =
            await _captureService.captureFrame(pixelRatio: pixelRatio);
        if (rgbaData != null) {
          await _renderService.appendFrame(rgbaData);
          setState(() {
            _capturedFrames++;
          });
        }
      }
    }

    // Clear the overlay after slideshow is done
    setState(() => _endingImageOverlay = null);
  }

  /// Get the overview camera that fits the entire route with padding.
  Future<CameraOptions?> _getOverviewCamera() async {
    if (_mapboxMap == null || widget.route.points.isEmpty) return null;

    try {
      double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
      for (final p in widget.route.points) {
        if (p.lat < minLat) minLat = p.lat;
        if (p.lat > maxLat) maxLat = p.lat;
        if (p.lng < minLng) minLng = p.lng;
        if (p.lng > maxLng) maxLng = p.lng;
      }

      final bounds = CoordinateBounds(
        southwest: Point(coordinates: Position(minLng, minLat)),
        northeast: Point(coordinates: Position(maxLng, maxLat)),
        infiniteBounds: false,
      );

      return await _mapboxMap!.cameraForCoordinateBounds(
        bounds,
        MbxEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
        0, // bearing
        0, // pitch (top-down for overview)
        null,
        null,
      );
    } catch (e) {
      debugPrint('Failed to compute overview camera: $e');
      return null;
    }
  }

  /// Add empty route source + layer and position marker to the map.
  /// The route trail starts empty and is progressively revealed.
  Future<void> _setupRouteOnMap(MapboxMap map) async {
    if (widget.route.points.isEmpty) return;

    final color = widget.config.routeColor;
    final colorInt = ((color.a * 255).round() << 24) |
        ((color.r * 255).round() << 16) |
        ((color.g * 255).round() << 8) |
        (color.b * 255).round();

    try {
      // Start with an empty GeoJSON line (will be revealed progressively)
      final emptyLine = LineString(coordinates: [
        Position(widget.route.points.first.lng, widget.route.points.first.lat),
      ]);
      await map.style.addSource(GeoJsonSource(
        id: 'route-source',
        data: json.encode(emptyLine.toJson()),
      ));

      await map.style.addLayer(LineLayer(
        id: 'route-layer',
        sourceId: 'route-source',
        lineColor: colorInt,
        lineWidth: widget.config.routeWidth,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
      ));

      // Create position marker (circle annotation)
      _positionMarkerManager =
          await map.annotations.createCircleAnnotationManager();
      final startPt = widget.route.points.first;
      await _positionMarkerManager!.create(
        CircleAnnotationOptions(
          geometry: Point(coordinates: Position(startPt.lng, startPt.lat)),
          circleColor: colorInt,
          circleRadius: 8.0,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 3.0,
        ),
      );

      // Hide all Mapbox ornaments
      map.compass.updateSettings(CompassSettings(enabled: false));
      map.logo.updateSettings(LogoSettings(enabled: false));
      map.attribution.updateSettings(AttributionSettings(enabled: false));
      map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    } catch (e) {
      debugPrint('Failed to setup route on map: $e');
    }
  }

  /// Update the route trail to reveal from start to current frame index.
  Future<void> _updateRouteTrail(int frameIndex) async {
    if (_mapboxMap == null) return;

    try {
      final points = _animController.interpolatedPoints;
      final endIdx = (frameIndex + 1).clamp(1, points.length);

      final trailCoords =
          points.sublist(0, endIdx).map((p) => Position(p.lng, p.lat)).toList();

      final lineString = LineString(coordinates: trailCoords);

      await _mapboxMap!.style.setStyleSourceProperty(
        'route-source',
        'data',
        json.encode(lineString.toJson()),
      );
    } catch (e) {
      debugPrint('Failed to update route trail: $e');
    }
  }

  /// Update the position marker to the current frame location
  Future<void> _updatePositionMarker(double lat, double lng) async {
    if (_positionMarkerManager == null) return;

    try {
      // Delete all existing and create new at updated position
      await _positionMarkerManager!.deleteAll();

      final color = widget.config.routeColor;
      final colorInt = ((color.a * 255).round() << 24) |
          ((color.r * 255).round() << 16) |
          ((color.g * 255).round() << 8) |
          (color.b * 255).round();

      await _positionMarkerManager!.create(
        CircleAnnotationOptions(
          geometry: Point(coordinates: Position(lng, lat)),
          circleColor: colorInt,
          circleRadius: 5.0,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 1.0,
        ),
      );
    } catch (e) {
      debugPrint('Failed to update position marker: $e');
    }
  }

  void _cancelRendering() {
    setState(() {
      _isCancelled = true;
      _phase = _RenderPhase.cancelled;
    });
  }

  String get _estimatedTimeRemaining {
    if (_startTime == null || _capturedFrames == 0) return 'Calculating...';

    final elapsed = DateTime.now().difference(_startTime!);
    final progress = _capturedFrames / _totalFrames;
    if (progress <= 0) return 'Calculating...';

    final totalEstimated = elapsed.inSeconds / progress;
    final remaining = totalEstimated - elapsed.inSeconds;

    if (remaining < 60) return '${remaining.round()}s remaining';
    return '${(remaining / 60).ceil()}m remaining';
  }

  double get _overallProgress {
    if (_totalFrames == 0) return 0;
    return switch (_phase) {
      _RenderPhase.initializing => 0.0,
      _RenderPhase.capturing => (_capturedFrames / _totalFrames) * 0.95,
      _RenderPhase.encoding => 0.95,
      _RenderPhase.complete => 1.0,
      _ => 0.0,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              // Map for capture (wrapped in RepaintBoundary)
              // Displayed at 1/4 scale; captured at 4x pixelRatio to match encoder resolution
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: widget.config.aspectRatio.width.toDouble() / 4,
                  height: widget.config.aspectRatio.height.toDouble() / 4,
                  child: RepaintBoundary(
                    key: _captureService.repaintBoundaryKey,
                    child: SizedBox(
                      width: widget.config.aspectRatio.width.toDouble() / 4,
                      height: widget.config.aspectRatio.height.toDouble() / 4,
                      child: Stack(
                        children: [
                          // Map (ornaments hidden via SDK settings)
                          Positioned.fill(
                            child: MapWidget(
                              cameraOptions: CameraOptions(
                                center: Point(
                                  coordinates: Position(
                                    widget.route.points.first.lng,
                                    widget.route.points.first.lat,
                                  ),
                                ),
                                zoom: 11.0, // Start zoomed out (overview)
                                pitch: 0.0, // Top-down for overview
                              ),
                              styleUri: widget.config.mapStyle.styleUri,
                              onMapCreated: (map) {
                                _mapboxMap = map;
                                // Setup route + position marker, then start rendering
                                _setupRouteOnMap(map).then((_) {
                                  Future.delayed(
                                    const Duration(seconds: 2),
                                    () {
                                      if (mounted) _startRendering();
                                    },
                                  );
                                });
                              },
                            ),
                          ),
                          // Dynamic stats overlay on top of map
                          StatsOverlayWidget(
                            route: widget.route,
                            config: widget.config,
                            currentFrameIndex: _currentFrameIndex,
                            interpolatedPoints:
                                _animController.interpolatedPoints,
                            fps: widget.config.fps,
                          ),
                          // Ending image overlay (shown during slideshow phase)
                          if (_endingImageOverlay != null) _endingImageOverlay!,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildPhaseIndicator(),
                      const SizedBox(height: 24),
                      _buildProgressBar(),
                      const SizedBox(height: 16),
                      _buildStats(),
                      const SizedBox(height: 24),
                      _buildActionButtons(),
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
            onPressed: () {
              if (_phase == _RenderPhase.capturing ||
                  _phase == _RenderPhase.encoding) {
                _showCancelDialog(context);
              } else {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.close_rounded),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.surfaceCard,
            ),
          ),
          const Spacer(),
          Text(
            _phase == _RenderPhase.complete ? 'Video Ready!' : 'Rendering...',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildPhaseIndicator() {
    final (icon, label, color) = switch (_phase) {
      _RenderPhase.initializing => (
          Icons.hourglass_top_rounded,
          'Preparing...',
          AppTheme.textSecondary,
        ),
      _RenderPhase.capturing => (
          Icons.camera_alt_rounded,
          'Capturing & Encoding',
          AppTheme.primaryColor,
        ),
      _RenderPhase.encoding => (
          Icons.movie_creation_rounded,
          'Finalizing...',
          AppTheme.accentColor,
        ),
      _RenderPhase.complete => (
          Icons.check_circle_rounded,
          'Complete!',
          AppTheme.successColor,
        ),
      _RenderPhase.error => (
          Icons.error_rounded,
          'Error',
          AppTheme.errorColor,
        ),
      _RenderPhase.cancelled => (
          Icons.cancel_rounded,
          'Cancelled',
          AppTheme.textSecondary,
        ),
    };

    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = _phase == _RenderPhase.complete
                ? 1.0
                : 1.0 + (_pulseController.value * 0.1);
            return Transform.scale(
              scale: scale,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.2),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(icon, size: 48, color: color),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          label,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _overallProgress,
            minHeight: 8,
            backgroundColor: AppTheme.surfaceElevated,
            valueColor: AlwaysStoppedAnimation<Color>(
              _phase == _RenderPhase.complete
                  ? AppTheme.successColor
                  : AppTheme.primaryColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(_overallProgress * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (_phase == _RenderPhase.capturing)
              Text(
                _estimatedTimeRemaining,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStats() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(
            'Frames',
            '$_capturedFrames / $_totalFrames',
            Icons.photo_library_rounded,
          ),
          Container(width: 1, height: 40, color: AppTheme.surfaceElevated),
          _buildStatItem(
            'Format',
            widget.config.aspectRatio.label,
            Icons.aspect_ratio_rounded,
          ),
          Container(width: 1, height: 40, color: AppTheme.surfaceElevated),
          _buildStatItem(
            'FPS',
            '${widget.config.fps}',
            Icons.speed_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppTheme.textSecondary),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    if (_phase == _RenderPhase.complete && _outputPath != null) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () async {
                try {
                  final hasPermission =
                      await _exportService.hasGalleryPermission();
                  if (!hasPermission) {
                    await _exportService.requestGalleryPermission();
                  }
                  await _exportService.saveToGallery(_outputPath!);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: AppTheme.successColor),
                            SizedBox(width: 12),
                            Text('Saved to gallery!'),
                          ],
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Save to Gallery'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () {
                _exportService.shareVideo(_outputPath!);
              },
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              Navigator.of(context)
                ..pop()
                ..pop();
            },
            child: const Text('Back to Activities'),
          ),
        ],
      );
    }

    if (_phase == _RenderPhase.error) {
      return Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _error!,
                style:
                    const TextStyle(color: AppTheme.errorColor, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back'),
            ),
          ),
        ],
      );
    }

    if (_phase == _RenderPhase.capturing || _phase == _RenderPhase.encoding) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          onPressed: _cancelRendering,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.errorColor,
            side: const BorderSide(color: AppTheme.errorColor),
          ),
          icon: const Icon(Icons.cancel_rounded),
          label: const Text('Cancel'),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  void _showCancelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Rendering?'),
        content: const Text(
          'Are you sure you want to cancel? All progress will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continue'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _cancelRendering();
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _animController.dispose();
    super.dispose();
  }
}

enum _RenderPhase {
  initializing,
  capturing,
  encoding,
  complete,
  error,
  cancelled,
}
