import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Captures widget content as raw RGBA pixel data for video encoding.
/// Uses RepaintBoundary to capture map snapshots frame-by-frame.
class FrameCaptureService {
  final GlobalKey repaintBoundaryKey = GlobalKey();
  int _capturedCount = 0;

  int get capturedCount => _capturedCount;

  /// Capture the current widget state as RGBA pixel data.
  /// Returns null if capture fails.
  Future<Uint8List?> captureFrame({double pixelRatio = 1.0}) async {
    try {
      final boundary = repaintBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;

      _capturedCount++;
      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('Frame capture failed: $e');
      return null;
    }
  }

  void reset() {
    _capturedCount = 0;
  }
}
