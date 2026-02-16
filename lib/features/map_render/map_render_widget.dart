import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../core/models/route_point.dart';
import '../../core/models/video_config.dart';

/// Widget that renders a Mapbox map with a route polyline.
/// Reacts to config changes (style, route color, camera) in real time.
class MapRenderWidget extends StatefulWidget {
  final List<RoutePoint> routePoints;
  final VideoConfig config;
  final void Function(MapboxMap mapboxMap)? onMapCreated;
  final bool interactive;

  const MapRenderWidget({
    super.key,
    required this.routePoints,
    required this.config,
    this.onMapCreated,
    this.interactive = true,
  });

  @override
  State<MapRenderWidget> createState() => _MapRenderWidgetState();
}

class _MapRenderWidgetState extends State<MapRenderWidget> {
  MapboxMap? _mapboxMap;
  bool _routeAdded = false;

  @override
  void didUpdateWidget(covariant MapRenderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final map = _mapboxMap;
    if (map == null) return;

    // Update map style if changed
    if (oldWidget.config.mapStyle != widget.config.mapStyle) {
      _updateMapStyle(map);
    }

    // Update camera if pitch or zoom changed
    if (oldWidget.config.cameraPitch != widget.config.cameraPitch ||
        oldWidget.config.cameraZoom != widget.config.cameraZoom) {
      _updateCamera(map);
    }

    // Update route color if changed
    if (oldWidget.config.routeColor != widget.config.routeColor ||
        oldWidget.config.routeWidth != widget.config.routeWidth) {
      _updateRouteStyle(map);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _calculateCenter(widget.routePoints);

    return MapWidget(
      cameraOptions: CameraOptions(
        center: Point(coordinates: Position(center.lng, center.lat)),
        zoom: widget.config.cameraZoom,
        pitch: widget.config.cameraPitch,
      ),
      styleUri: widget.config.mapStyle.styleUri,
      onMapCreated: _onMapCreated,
    );
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    _routeAdded = false;
    widget.onMapCreated?.call(mapboxMap);

    // Disable gestures if not interactive
    if (!widget.interactive) {
      mapboxMap.gestures.updateSettings(GesturesSettings(
        rotateEnabled: false,
        scrollEnabled: false,
        pitchEnabled: false,
        doubleTapToZoomInEnabled: false,
        doubleTouchToZoomOutEnabled: false,
        pinchToZoomEnabled: false,
        quickZoomEnabled: false,
      ));
    }

    _addRoutePolyline(mapboxMap);
    _hideMapOrnaments(mapboxMap);
  }

  /// Hide all Mapbox ornaments: compass, logo, attribution, scale bar.
  void _hideMapOrnaments(MapboxMap mapboxMap) {
    mapboxMap.compass.updateSettings(CompassSettings(enabled: false));
    mapboxMap.logo.updateSettings(LogoSettings(enabled: false));
    mapboxMap.attribution.updateSettings(AttributionSettings(enabled: false));
    mapboxMap.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
  }

  Future<void> _updateMapStyle(MapboxMap map) async {
    await map.style.setStyleURI(widget.config.mapStyle.styleUri);

    // After style change, layers are removed — re-add route after style loads
    _routeAdded = false;
    await Future.delayed(const Duration(milliseconds: 500));
    await _addRoutePolyline(map);
  }

  Future<void> _updateCamera(MapboxMap map) async {
    final center = _calculateCenter(widget.routePoints);
    await map.setCamera(CameraOptions(
      center: Point(coordinates: Position(center.lng, center.lat)),
      pitch: widget.config.cameraPitch,
      zoom: widget.config.cameraZoom,
    ));
  }

  Future<void> _updateRouteStyle(MapboxMap map) async {
    if (!_routeAdded) return;

    try {
      final colorInt = _colorToInt(widget.config.routeColor);

      // Remove existing layer and re-add with new style
      await map.style.removeStyleLayer('route-layer');
      await map.style.addLayer(LineLayer(
        id: 'route-layer',
        sourceId: 'route-source',
        lineColor: colorInt,
        lineWidth: widget.config.routeWidth,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
      ));
    } catch (e) {
      debugPrint('Failed to update route style: $e');
    }
  }

  Future<void> _addRoutePolyline(MapboxMap mapboxMap) async {
    if (widget.routePoints.isEmpty) return;

    final coordinates =
        widget.routePoints.map((p) => Position(p.lng, p.lat)).toList();

    final lineString = LineString(coordinates: coordinates);
    final colorInt = _colorToInt(widget.config.routeColor);

    try {
      // Remove existing source/layer if present
      if (_routeAdded) {
        try {
          await mapboxMap.style.removeStyleLayer('route-layer');
          await mapboxMap.style.removeStyleSource('route-source');
        } catch (_) {}
      }

      await mapboxMap.style.addSource(GeoJsonSource(
        id: 'route-source',
        data: json.encode(lineString.toJson()),
      ));

      await mapboxMap.style.addLayer(LineLayer(
        id: 'route-layer',
        sourceId: 'route-source',
        lineColor: colorInt,
        lineWidth: widget.config.routeWidth,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
      ));

      _routeAdded = true;
    } catch (e) {
      debugPrint('Failed to add route polyline: $e');
    }
  }

  int _colorToInt(Color color) {
    return ((color.a * 255).round() << 24) |
        ((color.r * 255).round() << 16) |
        ((color.g * 255).round() << 8) |
        (color.b * 255).round();
  }

  RoutePoint _calculateCenter(List<RoutePoint> points) {
    if (points.isEmpty) {
      return const RoutePoint(lat: 0, lng: 0);
    }

    double avgLat = 0, avgLng = 0;
    for (final p in points) {
      avgLat += p.lat;
      avgLng += p.lng;
    }
    return RoutePoint(
      lat: avgLat / points.length,
      lng: avgLng / points.length,
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
