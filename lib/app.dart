import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'features/gpx_import/gpx_import_bloc.dart';
import 'features/strava/strava_api_service.dart';
import 'features/strava/strava_auth_service.dart';
import 'ui/screens/activity_selection_screen.dart';
import 'ui/theme/app_theme.dart';

class FlyoverApp extends StatefulWidget {
  const FlyoverApp({super.key});

  @override
  State<FlyoverApp> createState() => _FlyoverAppState();
}

class _FlyoverAppState extends State<FlyoverApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _stravaAuth = StravaAuthService();
  late final AppLinks _appLinks;

  StreamSubscription? _shareIntentSub;
  StreamSubscription? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _initShareIntent();
    _initDeepLinks();
  }

  /// Listen for shared content from Strava.
  void _initShareIntent() {
    _shareIntentSub =
        ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      _handleSharedMedia(files);
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handleSharedMedia(files);
    });
  }

  Future<void> _handleSharedMedia(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    // Capture BLoC before async gap
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return;
    final bloc = ctx.read<GpxImportBloc>();

    // Find any image path from the shared files
    String? sharedImagePath;
    for (final file in files) {
      if (file.type == SharedMediaType.image) {
        sharedImagePath = file.path;
        break;
      }
    }

    // Check clipboard for a Strava activity URL (handles short links too)
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final clipText = clipboardData?.text ?? '';
    final activityId = await StravaApiService.resolveActivityId(clipText);
    if (activityId != null) {
      bloc.add(
        ImportStravaActivity(
          activityId,
          sharedImagePath: sharedImagePath,
        ),
      );
    }
  }

  /// Listen for deep link callbacks (OAuth redirect).
  void _initDeepLinks() {
    _deepLinkSub = _appLinks.uriLinkStream.listen((Uri uri) {
      _handleDeepLink(uri);
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.scheme == 'flyover' && uri.host == 'strava-callback') {
      await _stravaAuth.handleCallback(uri);
    }
  }

  @override
  void dispose() {
    _shareIntentSub?.cancel();
    _deepLinkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => GpxImportBloc()),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Flyover',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const ActivitySelectionScreen(),
      ),
    );
  }
}
