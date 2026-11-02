// End-to-end smoke test: the real app, on a real simulator, against a real
// backend. The unit and widget suites fake the socket, the API and the camera
// roll, so none of them can catch a plugin that fails to link, a photo
// permission that is never granted, or a build whose API_BASE points nowhere.
//
// Run it with the backend up:
//   flutter test integration_test/app_test.dart -d <device-id> \
//     --dart-define=API_BASE=http://localhost:8000
//
// The second player is driven straight over HTTP from inside the test rather
// than from a second device: what needs proving is that this device's UI
// reacts to someone else's actions arriving over its WebSocket, and a direct
// API call produces exactly the same broadcasts a second phone would.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:integration_test/integration_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_blame/config.dart';
import 'package:photo_blame/main.dart' as app;
import 'package:photo_blame/screens/lobby_screen.dart';
import 'package:photo_blame/ui/fit_text.dart';

/// Pumps in slices until [condition] holds, instead of `pumpAndSettle`.
///
/// The game screen runs a 1s periodic countdown, so the tree is never settled
/// once a round is live and `pumpAndSettle` would time out on every step.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('timed out waiting for ${reason ?? 'condition'}');
}

bool _visible(Finder f) => f.evaluate().isNotEmpty;

/// The five-character room code shown on the lobby's game-code card.
///
/// The code is the lobby's first poster line. Scoped to the lobby because the
/// home screen is still in the tree during the transition, and its "PHOTO"
/// looks exactly like a code. Names come after it, and "GUEST" would too.
String readRoomCode(WidgetTester tester) {
  final codes = tester
      .widgetList<FitText>(
        find.descendant(
          of: find.byType(LobbyScreen),
          matching: find.byType(FitText),
        ),
      )
      .map((t) => t.text)
      .where((s) => RegExp(r'^[A-Z0-9]{5}$').hasMatch(s))
      .toList();
  expect(codes, isNotEmpty, reason: 'the lobby should show a room code');
  return codes.first;
}

/// Any snackbar currently on screen, so a failure can say what the app said.
String? currentSnack(WidgetTester tester) {
  final snack = find.descendant(
    of: find.byType(SnackBar),
    matching: find.byType(Text),
  );
  if (snack.evaluate().isEmpty) return null;
  return tester.widgetList<Text>(snack).map((t) => t.data).join(' ');
}

/// A one-pixel JPEG, so the second player counts as having contributed.
final _jpeg = Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, //
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
  0x00, ...List<int>.filled(64, 0x08), 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00,
  0x01, 0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00,
  0x01, ...List<int>.filled(16, 0x00), 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01,
  0x00, 0x00, 0x3F, 0x00, 0xD2, 0xCF, 0x20, 0xFF, 0xD9,
]);

/// Whether photo-library access is usable in this run.
///
/// A first request pops a system alert, and `WidgetTester` drives the Flutter
/// view directly rather than through the window server, so nothing in this
/// test can dismiss it — the future would simply never complete. Granting it
/// ahead of time also does not survive: `flutter test` reinstalls the app on
/// every run, which resets the simulator's TCC decision.
///
/// So the request is raced against a short timeout. Pre-grant it with
/// `xcrun simctl privacy <device> grant photos com.photoblame.app` between
/// the install and the run to exercise the real picker path.
Future<bool> photoAccessGranted(WidgetTester tester) async {
  // runAsync: a real platform-channel round trip has to happen outside the
  // test's own async zone, or the reply is never delivered and the timeout
  // never fires either — the call simply hangs.
  final granted = await tester.runAsync(() async {
    final state = await PhotoManager.requestPermissionExtend().timeout(
      const Duration(seconds: 8),
      onTimeout: () => PermissionState.denied,
    );
    return state.isAuth || state.hasAccess;
  });
  return granted ?? false;
}

/// The player id the app itself joined with, read back off the room.
Future<String> readHostId(String code, String name) async {
  final resp = await http.get(Uri.parse('$apiBase/rooms/$code'));
  final players = (jsonDecode(resp.body) as Map<String, dynamic>)['players']
      as List<dynamic>;
  final me = players.firstWhere(
    (p) => (p as Map<String, dynamic>)['name'] == name,
  ) as Map<String, dynamic>;
  return me['id'] as String;
}

/// A second player, acting over the API the way another phone would.
class RemotePlayer {
  final String code;
  late final String id;
  final _http = http.Client();

  RemotePlayer(this.code);

  /// Act as an already-joined player, e.g. the one this device joined as.
  void joinAs(String playerId) => id = playerId;

  Future<void> join(String name) async {
    final resp = await _http.post(
      Uri.parse('$apiBase/rooms/$code/join'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );
    expect(resp.statusCode, 200, reason: 'join failed: ${resp.body}');
    id = (jsonDecode(resp.body) as Map<String, dynamic>)['player_id'] as String;
  }

  Future<void> uploadPhoto() async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiBase/rooms/$code/photos?owner_id=$id'),
    )..files.add(http.MultipartFile.fromBytes(
        'file',
        _jpeg,
        filename: 'photo.jpg',
        // The endpoint refuses anything not announced as an image, and the
        // default here is application/octet-stream.
        contentType: MediaType('image', 'jpeg'),
      ));
    final resp = await _http.send(request);
    expect(resp.statusCode, 200, reason: 'upload failed');
  }

  void close() => _http.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('host a game, play a round and reach the leaderboard',
      (tester) async {
    // The build under test must be pointed at a reachable backend; without
    // this the failure below would look like a UI bug.
    final health = await http.get(Uri.parse('$apiBase/health'));
    expect(health.statusCode, 200, reason: 'backend unreachable at $apiBase');

    app.main();
    await tester.pumpAndSettle();

    // --- home --------------------------------------------------------------
    expect(find.text('PHOTO'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Host');
    await tester.pump();
    await tester.tap(find.text('Start a game'));
    await pumpUntil(tester, () => _visible(find.byType(LobbyScreen)),
        reason: 'the lobby');

    final code = readRoomCode(tester);
    debugPrint('room: $code');

    // --- lobby: this device contributes photos from the camera roll --------
    // photo_manager, the permission and the simulator's photo library are all
    // real here, which is the part no widget test can stand in for.
    if (await photoAccessGranted(tester)) {
      await tester.tap(find.textContaining('dd photos'));
      // A snackbar instead means the sampler refused (empty roll, revoked
      // access), which would otherwise surface only as a bare timeout.
      await pumpUntil(
        tester,
        () => _visible(find.text('Use these')) || currentSnack(tester) != null,
        timeout: const Duration(seconds: 60),
        reason: 'the photo preview',
      );
      final refusal = currentSnack(tester);
      expect(refusal, isNull, reason: 'sampling photos was refused: $refusal');
      await tester.tap(find.text('Use these'));
      await pumpUntil(tester, () => _visible(find.textContaining('Added')),
          timeout: const Duration(seconds: 60), reason: 'the upload to finish');
    } else {
      // Contribute over the API instead, so every step after this one still
      // runs. See photoAccessGranted for when and why this happens.
      debugPrint('SKIPPED the camera-roll picker: no photo-library access');
      final self = RemotePlayer(code);
      addTearDown(self.close);
      self.joinAs(await readHostId(code, 'Host'));
      await self.uploadPhoto();
    }

    // --- a second player joins, over the socket ---------------------------
    final other = RemotePlayer(code);
    addTearDown(other.close);
    await other.join('Guest');
    await pumpUntil(tester, () => _visible(find.text('GUEST')),
        reason: "the roster to show the player who joined");
    await other.uploadPhoto();

    // START only unlocks once two different people have contributed, which is
    // the server's rule as well as the button's.
    await pumpUntil(tester, () => _visible(find.text('Start game')),
        reason: 'START to unlock once two players have photos');

    // Shortest game the lobby allows, so the round timer doesn't dominate.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Fewer Rounds'));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await pumpUntil(tester, () => _visible(find.text('1')),
        reason: 'the round count to reach 1');

    // --- the game ---------------------------------------------------------
    await tester.tap(find.text('Start game'));
    // Wait for the lobby to be *gone*, not just for the game to appear: both
    // routes are in the tree during the transition, and a chip tapped on the
    // outgoing one lands off-screen and does nothing.
    await pumpUntil(
      tester,
      () => _visible(find.textContaining('Round 1')) &&
          !_visible(find.byType(LobbyScreen)),
      reason: 'the game screen',
    );

    // Guessing is the whole point; the band is the other player's name.
    final guestBand = find.text('GUEST');
    await pumpUntil(tester, () => _visible(guestBand),
        reason: 'the guess bands');
    await tester.tap(guestBand);
    // The instant banner is the proof the guess actually reached the server;
    // without it the round would simply time out and still reveal.
    await pumpUntil(
      tester,
      () => _visible(find.textContaining('Correct!')) ||
          _visible(find.textContaining('Guess submitted')),
      reason: 'the guess to be acknowledged',
    );

    // --- results ----------------------------------------------------------
    await pumpUntil(tester, () => _visible(find.text('Leave game')),
        timeout: const Duration(seconds: 60), reason: 'the leaderboard');
    expect(find.text('HOST'), findsWidgets);
  });
}
