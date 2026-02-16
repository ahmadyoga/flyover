import 'dart:typed_data';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/models/video_config.dart';

/// Encodes captured RGBA frames into an MP4 video using
/// native hardware H.264 encoder (no FFmpeg dependency).
class VideoRenderService {
  /// Callback for rendering progress (0.0 to 1.0).
  void Function(double progress)? onProgress;

  bool _isSetup = false;

  /// Set up the video encoder with the given configuration.
  /// Returns the output file path.
  Future<String> setup(VideoConfig config) async {
    final outputDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${outputDir.path}/flyover_$timestamp.mp4';

    final width = config.aspectRatio.width;
    final height = config.aspectRatio.height;

    await FlutterQuickVideoEncoder.setup(
      width: width,
      height: height,
      fps: config.fps,
      videoBitrate: 5000000, // 5 Mbps for quality
      profileLevel: ProfileLevel.any,
      audioChannels: 0,
      audioBitrate: 0,
      sampleRate: 0,
      filepath: outputPath,
    );

    _isSetup = true;
    return outputPath;
  }

  /// Append a single RGBA frame to the video.
  Future<void> appendFrame(Uint8List rgbaData) async {
    if (!_isSetup) {
      throw VideoRenderException('VideoRenderService not set up. Call setup() first.');
    }
    await FlutterQuickVideoEncoder.appendVideoFrame(rgbaData);
  }

  /// Finalize the video file. Must be called after all frames are appended.
  Future<void> finish() async {
    if (!_isSetup) return;
    await FlutterQuickVideoEncoder.finish();
    _isSetup = false;
  }
}

/// Custom exception for video rendering errors.
class VideoRenderException implements Exception {
  final String message;
  VideoRenderException(this.message);

  @override
  String toString() => 'VideoRenderException: $message';
}
