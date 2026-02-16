import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';

enum VideoAspectRatio {
  landscape16x9('16:9', 16 / 9),
  portrait9x16('9:16', 9 / 16);

  final String label;
  final double ratio;
  const VideoAspectRatio(this.label, this.ratio);

  int get width => this == landscape16x9 ? 1920 : 1080;
  int get height => this == landscape16x9 ? 1080 : 1920;
}

enum MapStyle {
  // Mapbox Standard
  standard('Standard', 'mapbox://styles/mapbox/standard'),
  standardSatellite(
      'Standard Satellite', 'mapbox://styles/mapbox/standard-satellite'),

  // Classic
  streets('Streets', 'mapbox://styles/mapbox/streets-v12'),
  outdoors('Outdoors', 'mapbox://styles/mapbox/outdoors-v12'),
  light('Light', 'mapbox://styles/mapbox/light-v11'),
  dark('Dark', 'mapbox://styles/mapbox/dark-v11'),
  satellite('Satellite', 'mapbox://styles/mapbox/satellite-v9'),
  satelliteStreets(
      'Satellite Streets', 'mapbox://styles/mapbox/satellite-streets-v12'),
  navigationDay('Navigation Day', 'mapbox://styles/mapbox/navigation-day-v1'),
  navigationNight(
      'Navigation Night', 'mapbox://styles/mapbox/navigation-night-v1');

  final String label;
  final String styleUri;
  const MapStyle(this.label, this.styleUri);
}

enum SpeedFormat {
  kmh('km/h'),
  minPerKm('min/km');

  final String label;
  const SpeedFormat(this.label);
}

class VideoConfig extends Equatable {
  final VideoAspectRatio aspectRatio;
  final MapStyle mapStyle;
  final Color routeColor;
  final double routeWidth;
  final int videoDurationSeconds;
  final bool showOverlay;
  final bool showActivityName;
  final bool showDistance;
  final bool showPace;
  final bool showElevation;
  final bool showSpeed;
  final SpeedFormat speedFormat;
  final int fps;
  final double cameraPitch;
  final double cameraZoom;

  /// Absolute paths of images to display after the route flyover.
  final List<String> endingImagePaths;

  const VideoConfig({
    this.aspectRatio = VideoAspectRatio.portrait9x16,
    this.mapStyle = MapStyle.dark,
    this.routeColor = const Color(0xFF00E5FF),
    this.routeWidth = 4.0,
    this.videoDurationSeconds = 60,
    this.showOverlay = true,
    this.showActivityName = true,
    this.showDistance = true,
    this.showPace = true,
    this.showElevation = true,
    this.showSpeed = true,
    this.speedFormat = SpeedFormat.kmh,
    this.fps = 30,
    this.cameraPitch = 60.0,
    this.cameraZoom = 15.5,
    this.endingImagePaths = const [],
  });

  VideoConfig copyWith({
    VideoAspectRatio? aspectRatio,
    MapStyle? mapStyle,
    Color? routeColor,
    double? routeWidth,
    int? videoDurationSeconds,
    bool? showOverlay,
    bool? showActivityName,
    bool? showDistance,
    bool? showPace,
    bool? showElevation,
    bool? showSpeed,
    SpeedFormat? speedFormat,
    int? fps,
    double? cameraPitch,
    double? cameraZoom,
    List<String>? endingImagePaths,
  }) {
    return VideoConfig(
      aspectRatio: aspectRatio ?? this.aspectRatio,
      mapStyle: mapStyle ?? this.mapStyle,
      routeColor: routeColor ?? this.routeColor,
      routeWidth: routeWidth ?? this.routeWidth,
      videoDurationSeconds: videoDurationSeconds ?? this.videoDurationSeconds,
      showOverlay: showOverlay ?? this.showOverlay,
      showActivityName: showActivityName ?? this.showActivityName,
      showDistance: showDistance ?? this.showDistance,
      showPace: showPace ?? this.showPace,
      showElevation: showElevation ?? this.showElevation,
      showSpeed: showSpeed ?? this.showSpeed,
      speedFormat: speedFormat ?? this.speedFormat,
      fps: fps ?? this.fps,
      cameraPitch: cameraPitch ?? this.cameraPitch,
      cameraZoom: cameraZoom ?? this.cameraZoom,
      endingImagePaths: endingImagePaths ?? this.endingImagePaths,
    );
  }

  @override
  List<Object?> get props => [
        aspectRatio,
        mapStyle,
        routeColor,
        routeWidth,
        videoDurationSeconds,
        showOverlay,
        showActivityName,
        showDistance,
        showPace,
        showElevation,
        showSpeed,
        speedFormat,
        fps,
        cameraPitch,
        cameraZoom,
        endingImagePaths,
      ];
}
