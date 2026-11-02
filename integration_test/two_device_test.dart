// Two real devices in one room, playing each other.
//
// `app_test.dart` proves one device reacts to another player's actions, but
// the other player there is an HTTP client in the same process. This one runs
// on two simulators at once: both join the same pre-created room through the
// app's own JOIN GAME flow, the first one in hosts and starts the game, and
// both have to reach the same leaderboard.
//
//   scripts/run-two-device-test.sh
//
// The room code is created by that script and handed to both runs, because
// there is no way for one device to tell the other what code it drew.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:integration_test/integration_test.dart';
import 'package:photo_blame/config.dart';
import 'package:photo_blame/main.dart' as app;
import 'package:photo_blame/screens/lobby_screen.dart';
import 'package:photo_blame/ui/player_avatar.dart';

const roomCode = String.fromEnvironment('ROOM_CODE');
const playerName = String.fromEnvironment('PLAYER_NAME', defaultValue: 'Player');

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 45),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('$playerName timed out waiting for ${reason ?? 'condition'}');
}

bool _visible(Finder f) => f.evaluate().isNotEmpty;

/// A one-pixel JPEG. The camera-roll picker needs a human to answer the photo
/// permission alert, which nothing in a test can do, so each device
/// contributes its photo over the API as itself — see app_test.dart.
final _jpeg = Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, //
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
  0x00, ...List<int>.filled(64, 0x08), 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00,
  0x01, 0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00,
  0x01, ...List<int>.filled(16, 0x00), 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01,
  0x00, 0x00, 0x3F, 0x00, 0xD2, 0xCF, 0x20, 0xFF, 0xD9,
]);

Future<Map<String, dynamic>> _room() async {
  final resp = await http.get(Uri.parse('$apiBase/rooms/$roomCode'));
  return jsonDecode(resp.body) as Map<String, dynamic>;
}

Future<String> _myId() async {
  final players = (await _room())['players'] as List<dynamic>;
  final me = players.firstWhere(
    (p) => (p as Map<String, dynamic>)['name'] == playerName,
    orElse: () => throw StateError('$playerName is not in room $roomCode'),
  ) as Map<String, dynamic>;
  return me['id'] as String;
}

Future<void> _uploadAs(String playerId) async {
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('$apiBase/rooms/$roomCode/photos?owner_id=$playerId'),
  )..files.add(http.MultipartFile.fromBytes(
      'file',
      _jpeg,
      filename: 'photo.jpg',
      contentType: MediaType('image', 'jpeg'),
    ));
  final resp = await request.send();
  expect(resp.statusCode, 200, reason: 'upload failed for $playerName');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two devices play the same room to a shared leaderboard',
      (tester) async {
    expect(roomCode, isNotEmpty,
        reason: 'pass --dart-define=ROOM_CODE=<code>');

    app.main();
    await tester.pumpAndSettle();

    // --- join, through the app's own UI -----------------------------------
    await tester.enterText(find.byType(TextField).first, playerName);
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, roomCode);
    await tester.pump();
    await tester.tap(find.text('Join game'));
    await pumpUntil(tester, () => _visible(find.byType(LobbyScreen)),
        reason: 'the lobby for $roomCode');
    debugPrint('$playerName joined $roomCode');

    await _uploadAs(await _myId());

    // Both devices must see each other; this is the roster arriving over each
    // one's own WebSocket, not a poll.
    await pumpUntil(
      tester,
      () => _visible(find.text('Players (2)')),
      timeout: const Duration(seconds: 120),
      reason: 'the other device to appear in the roster',
    );

    // --- the host, whoever got in first, runs the game ---------------------
    final isHost = _visible(find.text('Change'));
    debugPrint('$playerName isHost=$isHost');

    if (isHost) {
      await pumpUntil(tester, () => _visible(find.text('Start game')),
          timeout: const Duration(seconds: 120),
          reason: 'START to unlock');
      await tester.tap(find.text('Change'));
      await pumpUntil(tester, () => _visible(find.byTooltip('Fewer Rounds')),
          reason: 'the settings sheet');
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('Fewer Rounds'));
        await tester.pump(const Duration(milliseconds: 300));
      }
      Navigator.of(tester.element(find.text('Game settings'))).pop();
      await pumpUntil(tester, () => !_visible(find.text('Game settings')),
          reason: 'the settings sheet to close');
      await tester.tap(find.text('Start game'));
    }

    // --- both play the round ----------------------------------------------
    await pumpUntil(
      tester,
      () => _visible(find.textContaining('Round 1')) &&
          !_visible(find.byType(LobbyScreen)),
      timeout: const Duration(seconds: 120),
      reason: 'the game screen',
    );

    final anyButton = find.byType(PlayerAvatar);
    await pumpUntil(tester, () => _visible(anyButton),
        reason: 'the guess buttons');
    await tester.tap(anyButton.first);
    await pumpUntil(
      tester,
      () => _visible(find.textContaining('Correct!')) ||
          _visible(find.textContaining('Guess submitted')),
      reason: 'the guess to be acknowledged',
    );

    // --- both land on the same leaderboard ---------------------------------
    await pumpUntil(tester, () => _visible(find.text('Leave game')),
        timeout: const Duration(seconds: 120), reason: 'the leaderboard');
    expect(find.text(playerName), findsWidgets,
        reason: 'this device should be on the board');
  });
}
