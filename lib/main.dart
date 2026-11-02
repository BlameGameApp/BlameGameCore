import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The round screen needs height for the photo and the names under it, and
  // the game is played holding the phone in one hand.
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
      // Every screen is light, whatever the system setting. Without this a
      // phone in dark mode draws a white clock on a white screen.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
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
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Not configured', style: text.headlineSmall),
              const SizedBox(height: 12),
              Text(problem, style: text.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
