import 'dart:io';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

/// Handles exporting videos to gallery and sharing to social media.
class ExportService {
  /// Save a video file to the device gallery.
  Future<void> saveToGallery(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) {
      throw ExportException('Video file not found: $videoPath');
    }

    try {
      await Gal.putVideo(videoPath, album: 'Flyover');
    } catch (e) {
      throw ExportException('Failed to save to gallery: $e');
    }
  }

  /// Share a video file using the system share sheet.
  Future<void> shareVideo(String videoPath, {String? message}) async {
    final file = File(videoPath);
    if (!await file.exists()) {
      throw ExportException('Video file not found: $videoPath');
    }

    try {
      await Share.shareXFiles(
        [XFile(videoPath)],
        text: message ?? 'Check out my flyover video! 🏃‍♂️🎥',
      );
    } catch (e) {
      throw ExportException('Failed to share video: $e');
    }
  }

  /// Check if gallery permission is granted.
  Future<bool> hasGalleryPermission() async {
    return await Gal.hasAccess();
  }

  /// Request gallery permission.
  Future<bool> requestGalleryPermission() async {
    return await Gal.requestAccess();
  }
}

/// Custom exception for export errors.
class ExportException implements Exception {
  final String message;
  ExportException(this.message);

  @override
  String toString() => 'ExportException: $message';
}
