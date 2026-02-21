import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/models/route_data.dart';
import '../../core/algorithms/pause_filter.dart';
import '../../core/algorithms/route_simplifier.dart';
import '../strava/strava_api_service.dart';
import 'gpx_parser_service.dart';

// --- Events ---

abstract class GpxImportEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class PickGpxFile extends GpxImportEvent {}

class ImportGpxFromPath extends GpxImportEvent {
  final String filePath;
  ImportGpxFromPath(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

class DeleteRoute extends GpxImportEvent {
  final String routeId;
  DeleteRoute(this.routeId);

  @override
  List<Object?> get props => [routeId];
}

class ImportStravaActivity extends GpxImportEvent {
  final int activityId;
  final String? sharedImagePath;
  ImportStravaActivity(this.activityId, {this.sharedImagePath});

  @override
  List<Object?> get props => [activityId, sharedImagePath];
}

class ClearPendingSharedImage extends GpxImportEvent {}

// --- State ---

class GpxImportState extends Equatable {
  final List<RouteData> routes;
  final bool isLoading;
  final String? error;
  final String? pendingSharedImagePath;

  const GpxImportState({
    this.routes = const [],
    this.isLoading = false,
    this.error,
    this.pendingSharedImagePath,
  });

  GpxImportState copyWith({
    List<RouteData>? routes,
    bool? isLoading,
    String? error,
    String? pendingSharedImagePath,
    bool clearPendingImage = false,
  }) {
    return GpxImportState(
      routes: routes ?? this.routes,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      pendingSharedImagePath: clearPendingImage
          ? null
          : pendingSharedImagePath ?? this.pendingSharedImagePath,
    );
  }

  @override
  List<Object?> get props => [routes, isLoading, error, pendingSharedImagePath];
}

// --- BLoC ---

class GpxImportBloc extends Bloc<GpxImportEvent, GpxImportState> {
  final GpxParserService _parserService;
  final StravaApiService _stravaService;

  GpxImportBloc({
    GpxParserService? parserService,
    StravaApiService? stravaService,
  })  : _parserService = parserService ?? GpxParserService(),
        _stravaService = stravaService ?? StravaApiService(),
        super(const GpxImportState()) {
    on<PickGpxFile>(_onPickGpxFile);
    on<ImportGpxFromPath>(_onImportFromPath);
    on<DeleteRoute>(_onDeleteRoute);
    on<ImportStravaActivity>(_onImportStravaActivity);
    on<ClearPendingSharedImage>((event, emit) {
      emit(state.copyWith(clearPendingImage: true));
    });
  }

  Future<void> _onPickGpxFile(
    PickGpxFile event,
    Emitter<GpxImportState> emit,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      // Validate file extension manually
      final lowerPath = filePath.toLowerCase();
      if (!lowerPath.endsWith('.gpx') && !lowerPath.endsWith('.xml')) {
        emit(state.copyWith(
          isLoading: false,
          error: 'Please select a GPX file (.gpx or .xml)',
        ));
        return;
      }

      emit(state.copyWith(isLoading: true, error: null));

      final routeData = await _parserService.parseFile(filePath);

      // Calculate moving duration (total time minus pause gaps)
      final movingDuration = PauseFilter.calculateMovingDuration(routeData.points);

      // Simplify the route to reduce noise (keep all points for distance)
      final simplifiedPoints = RouteSimplifier.simplify(
        routeData.points,
        epsilon: 3.0,
      );

      final simplifiedRoute = RouteData(
        id: routeData.id,
        name: routeData.name,
        points: simplifiedPoints,
        totalDistanceMeters: routeData.totalDistanceMeters,
        totalDuration: routeData.totalDuration,
        movingDuration: movingDuration,
        startTime: routeData.startTime,
        sourceFile: routeData.sourceFile,
      );

      emit(state.copyWith(
        routes: [...state.routes, simplifiedRoute],
        isLoading: false,
      ));
    } on GpxParseException catch (e) {
      emit(state.copyWith(isLoading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to import GPX file: $e',
      ));
    }
  }

  Future<void> _onImportFromPath(
    ImportGpxFromPath event,
    Emitter<GpxImportState> emit,
  ) async {
    try {
      emit(state.copyWith(isLoading: true, error: null));

      final routeData = await _parserService.parseFile(event.filePath);

      final movingDuration = PauseFilter.calculateMovingDuration(routeData.points);

      final simplifiedPoints = RouteSimplifier.simplify(
        routeData.points,
        epsilon: 3.0,
      );

      final simplifiedRoute = RouteData(
        id: routeData.id,
        name: routeData.name,
        points: simplifiedPoints,
        totalDistanceMeters: routeData.totalDistanceMeters,
        totalDuration: routeData.totalDuration,
        movingDuration: movingDuration,
        startTime: routeData.startTime,
        sourceFile: routeData.sourceFile,
      );

      emit(state.copyWith(
        routes: [...state.routes, simplifiedRoute],
        isLoading: false,
      ));
    } on GpxParseException catch (e) {
      emit(state.copyWith(isLoading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to import GPX file: $e',
      ));
    }
  }

  void _onDeleteRoute(
    DeleteRoute event,
    Emitter<GpxImportState> emit,
  ) {
    emit(state.copyWith(
      routes: state.routes.where((r) => r.id != event.routeId).toList(),
    ));
  }

  Future<void> _onImportStravaActivity(
    ImportStravaActivity event,
    Emitter<GpxImportState> emit,
  ) async {
    try {
      // Check for duplicates
      final stravaId = 'strava_${event.activityId}';
      if (state.routes.any((r) => r.id == stravaId)) {
        emit(state.copyWith(
          isLoading: false,
          error: 'Activity already imported.',
        ));
        return;
      }

      emit(state.copyWith(isLoading: true, error: null));

      final routeData =
          await _stravaService.fetchActivityAsRoute(event.activityId);

      final movingDuration = PauseFilter.calculateMovingDuration(routeData.points)
          ?? routeData.movingDuration;

      // Simplify the route to reduce noise
      final simplifiedPoints = RouteSimplifier.simplify(
        routeData.points,
        epsilon: 3.0,
      );

      final simplifiedRoute = RouteData(
        id: routeData.id,
        name: routeData.name,
        points: simplifiedPoints,
        totalDistanceMeters: routeData.totalDistanceMeters,
        totalDuration: routeData.totalDuration,
        movingDuration: movingDuration,
        startTime: routeData.startTime,
        sourceFile: routeData.sourceFile,
      );

      emit(state.copyWith(
        routes: [...state.routes, simplifiedRoute],
        isLoading: false,
        pendingSharedImagePath: event.sharedImagePath,
      ));
    } on StravaApiException catch (e) {
      emit(state.copyWith(isLoading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to import Strava activity: $e',
      ));
    }
  }
}
