/// App configuration.
library;

import 'package:flutter/foundation.dart';

/// Base URL of the REST API, e.g. `https://photo-blame.up.railway.app`.
///
/// Debug and profile builds fall back to localhost so `flutter run` just
/// works. Release builds deliberately do **not**: an IPA that quietly points
/// at the device's own loopback fails every single call with nothing to
/// diagnose it by, and iOS App Transport Security refuses cleartext HTTP
/// anyway. A release build is expected to carry the deployed backend:
///
///   flutter build ipa --dart-define=API_BASE=https://HOST
///
/// [apiBaseProblem] is what turns a missing or unusable value into a visible
/// failure at startup rather than a spinner that never resolves.
const String apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: kReleaseMode ? '' : 'http://localhost:8000',
);

/// Why [apiBase] cannot be used, or null when it is fine.
String? get apiBaseProblem =>
    apiBaseProblemFor(apiBase, release: kReleaseMode);

/// The rule behind [apiBaseProblem], separated from the compile-time constants
/// so both branches can be tested — a test binary is never a release build, so
/// the release rules are otherwise unreachable.
///
/// Both cases are build-time mistakes rather than anything a player did, so
/// the wording is aimed at whoever cut the build.
String? apiBaseProblemFor(String base, {required bool release}) {
  if (base.isEmpty) {
    return 'This build has no backend URL.\n\n'
        'Rebuild it with --dart-define=API_BASE=https://your-backend.';
  }
  if (release && !base.startsWith('https://')) {
    return 'The backend URL must be https in a release build, and this one '
        'is "$base".\n\n'
        'iOS blocks cleartext HTTP, so every request would fail.';
  }
  return null;
}

/// How many random photos to auto-sample from the camera roll per player.
const int photoSampleCount = 5;

/// The server refuses uploads past this, so the lobby stops offering them.
const int maxPhotosPerPlayer = 10;

/// WebSocket base URL, derived from [apiBase] by swapping the scheme
/// (`http`->`ws`, `https`->`wss`).
String get wsBase => wsBaseFor(apiBase);

/// The scheme swap behind [wsBase].
String wsBaseFor(String base) => base.replaceFirst(RegExp(r'^http'), 'ws');
