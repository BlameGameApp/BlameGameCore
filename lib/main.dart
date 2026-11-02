import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'ui/band.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Every screen is a tall stack of bands. Sideways there is no height to put
  // them in, and the lobby alone needs more than a landscape phone has.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const PhotoBlameApp());
}

class PhotoBlameApp extends StatelessWidget {
  const PhotoBlameApp({super.key});

  @override
  Widget build(BuildContext context) {
    final problem = apiBaseProblem;
    return MaterialApp(
      title: 'Photo Blame',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Poster type ignores the system text size, since it's already as big as
      // its band. Small text honours it up to the point where a full lobby on
      // a small phone would run out of height.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: child!,
      ),
      // A build with no usable backend can't do anything at all, so it says so
      // on the first screen instead of letting every action fail one spinner
      // at a time — which is what a TestFlight tester would otherwise report.
      home: problem == null
          ? const HomeScreen()
          : _MisconfiguredScreen(problem: problem),
    );
  }
}

class _MisconfiguredScreen extends StatelessWidget {
  final String problem;

  const _MisconfiguredScreen({required this.problem});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PosterScaffold(
      top: colors.vermilion,
      body: Band(
        color: colors.vermilion,
        padding: const EdgeInsets.all(bandGutter),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Not configured', style: uiText(34, weight: 900)),
              const SizedBox(height: 12),
              Text(problem, style: uiText(16)),
            ],
          ),
        ),
      ),
    );
  }
}
