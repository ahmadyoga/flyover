import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'features/gpx_import/gpx_import_bloc.dart';
import 'ui/screens/activity_selection_screen.dart';
import 'ui/theme/app_theme.dart';

class FlyoverApp extends StatelessWidget {
  const FlyoverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => GpxImportBloc()),
      ],
      child: MaterialApp(
        title: 'Flyover',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const ActivitySelectionScreen(),
      ),
    );
  }
}
