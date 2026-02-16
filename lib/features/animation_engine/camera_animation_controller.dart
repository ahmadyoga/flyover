import 'dart:async';
import '../../core/models/route_point.dart';
import '../../core/algorithms/bearing_calculator.dart';
import '../../core/algorithms/route_interpolator.dart';

/// Controls the camera flyover animation along a route.
/// Manages timing, frame progression, and camera parameters.
class CameraAnimationController {
  final List<RoutePoint> _interpolatedPoints;
  final double cameraPitch;
  final double cameraZoom;
  final int fps;

  int _currentFrame = 0;
  double _speedMultiplier = 1.0;
  bool _isPlaying = false;
  bool _isDisposed = false;
  Timer? _timer;

  /// Callback invoked for each frame with camera parameters.
  void Function(CameraFrame frame)? onFrame;

  /// Callback invoked when animation completes.
  void Function()? onComplete;

  /// Callback invoked when animation state changes.
  void Function(bool isPlaying)? onStateChanged;

  CameraAnimationController({
    required List<RoutePoint> routePoints,
    this.cameraPitch = 60.0,
    this.cameraZoom = 15.5,
    this.fps = 30,
    required int totalFrameCount,
  }) : _interpolatedPoints = RouteInterpolator.interpolateToCount(
          routePoints,
          targetCount: totalFrameCount,
        );

  int get totalFrames => _interpolatedPoints.length;
  int get currentFrame => _currentFrame;
  bool get isPlaying => _isPlaying;
  double get progress =>
      totalFrames > 0 ? _currentFrame / (totalFrames - 1) : 0;
  double get speedMultiplier => _speedMultiplier;

  List<RoutePoint> get interpolatedPoints => _interpolatedPoints;

  /// Start or resume the animation.
  void play() {
    if (_isDisposed || _isPlaying) return;
    if (_currentFrame >= totalFrames - 1) _currentFrame = 0;

    _isPlaying = true;
    onStateChanged?.call(true);

    final frameDuration = Duration(
      milliseconds: (1000 / (fps * _speedMultiplier)).round(),
    );

    _timer = Timer.periodic(frameDuration, (_) {
      if (_currentFrame >= totalFrames - 1) {
        pause();
        onComplete?.call();
        return;
      }
      _emitCurrentFrame();
      _currentFrame++;
    });
  }

  /// Pause the animation.
  void pause() {
    _timer?.cancel();
    _timer = null;
    _isPlaying = false;
    onStateChanged?.call(false);
  }

  /// Restart from the beginning.
  void restart() {
    pause();
    _currentFrame = 0;
    _emitCurrentFrame();
  }

  /// Seek to a specific frame.
  void seekToFrame(int frame) {
    _currentFrame = frame.clamp(0, totalFrames - 1);
    _emitCurrentFrame();
  }

  /// Seek to a progress value (0.0 - 1.0).
  void seekToProgress(double progress) {
    seekToFrame((progress * (totalFrames - 1)).round());
  }

  /// Set the animation speed multiplier.
  void setSpeed(double multiplier) {
    _speedMultiplier = multiplier.clamp(0.25, 4.0);
    if (_isPlaying) {
      pause();
      play();
    }
  }

  /// Get camera frame data for the current position.
  CameraFrame getCurrentFrame() {
    final index = _currentFrame.clamp(0, _interpolatedPoints.length - 1);
    final point = _interpolatedPoints[index];

    final bearing = BearingCalculator.calculateSmoothedBearing(
      _interpolatedPoints,
      index,
      windowSize: 5,
    );

    return CameraFrame(
      frameIndex: _currentFrame,
      center: point,
      bearing: bearing,
      pitch: cameraPitch,
      zoom: _dynamicZoom(index),
      progress: progress,
    );
  }

  void _emitCurrentFrame() {
    onFrame?.call(getCurrentFrame());
  }

  /// Calculate dynamic zoom based on route curvature.
  double _dynamicZoom(int index) {
    // Zoom out slightly on curves for better context
    if (index < 2 || index >= _interpolatedPoints.length - 2) {
      return cameraZoom;
    }

    final prevBearing = BearingCalculator.calculateBearing(
      _interpolatedPoints[index - 1],
      _interpolatedPoints[index],
    );
    final nextBearing = BearingCalculator.calculateBearing(
      _interpolatedPoints[index],
      _interpolatedPoints[index + 1],
    );

    var angleDiff = (nextBearing - prevBearing).abs();
    if (angleDiff > 180) angleDiff = 360 - angleDiff;

    // Zoom out on sharp turns (>30 degrees)
    if (angleDiff > 30) {
      final zoomReduction = (angleDiff / 180) * 1.5;
      return (cameraZoom - zoomReduction).clamp(14.0, 17.0);
    }

    return cameraZoom;
  }

  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// Represents camera parameters for a single animation frame.
class CameraFrame {
  final int frameIndex;
  final RoutePoint center;
  final double bearing;
  final double pitch;
  final double zoom;
  final double progress;

  const CameraFrame({
    required this.frameIndex,
    required this.center,
    required this.bearing,
    required this.pitch,
    required this.zoom,
    required this.progress,
  });
}
