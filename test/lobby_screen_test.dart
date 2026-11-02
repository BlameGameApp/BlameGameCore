import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_blame/models/game_models.dart';
import 'package:photo_blame/screens/lobby_screen.dart';

import 'support/fakes.dart';
import 'support/pump.dart';

void main() {
  testWidgets('shows the room code and everyone in it', (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    expect(find.text('ABC12'), findsOneWidget);
    expect(find.text('Emma (you)'), findsOneWidget);
    expect(find.text('Host, no photos yet'), findsOneWidget);
    expect(find.text('Jake'), findsOneWidget);
    expect(find.text('Players (2)'), findsOneWidget);
  });

  testWidgets('the main button is always the next thing to do',
      (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    // Nothing uploaded yet, so that comes first.
    expect(find.text('Add photos'), findsOneWidget);
    expect(find.text('Start game'), findsNothing);

    await h.emit(
      tester,
      PhotosUpdated([
        player(id: 'me', name: 'Emma', isHost: true, photoCount: 3),
        player(id: 'p2', name: 'Jake'),
      ]),
    );

    // One uploader isn't enough, and the button says what's being waited for.
    expect(find.text('Waiting for another player to add photos'), findsOneWidget);
    expect(find.text('Add more photos'), findsOneWidget);

    await h.emit(
      tester,
      PhotosUpdated([
        player(id: 'me', name: 'Emma', isHost: true, photoCount: 3),
        player(id: 'p2', name: 'Jake', photoCount: 1),
      ]),
    );

    expect(find.text('Start game'), findsOneWidget);
    expect(find.text('Add more photos'), findsOneWidget);
  });

  testWidgets('a host with no photos can still start once two others have',
      (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    await h.emit(
      tester,
      PhotosUpdated([
        player(id: 'me', name: 'Emma', isHost: true),
        player(id: 'p2', name: 'Jake', photoCount: 1),
        player(id: 'p3', name: 'Mia', photoCount: 1),
      ]),
    );

    expect(find.text('Start game'), findsOneWidget);
    expect(find.text('Add photos'), findsOneWidget);
  });

  testWidgets('photos stop being offered at the server limit', (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    await h.emit(
      tester,
      PhotosUpdated([
        player(id: 'me', name: 'Emma', isHost: true, photoCount: 10),
        player(id: 'p2', name: 'Jake', photoCount: 1),
      ]),
    );

    expect(find.text('Add more photos'), findsNothing);
  });

  testWidgets('tapping the code copies it, without covering the main button',
      (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.tap(find.text('ABC12'));
    await tester.pump();
    await tester.pump();

    expect(copied, 'ABC12');
    expect(find.text('Copied'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('players show real readiness, not a decorative tick',
      (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    // Nobody has uploaded, and every row says so.
    expect(find.text('0 of 2 ready'), findsOneWidget);
    expect(find.text('No photos yet'), findsOneWidget);

    await h.emit(
      tester,
      PhotosUpdated([
        player(id: 'me', name: 'Emma', isHost: true, photoCount: 1),
        player(id: 'p2', name: 'Jake', photoCount: 3),
      ]),
    );

    expect(find.text('2 of 2 ready'), findsOneWidget);
    expect(find.text('Host, 1 photo'), findsOneWidget);
    expect(find.text('3 photos'), findsOneWidget);
  });

  testWidgets('a non-host sees no start button', (tester) async {
    final h = await harness(isHost: false);
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    expect(find.text('Start game'), findsNothing);
    expect(find.text('Add photos'), findsOneWidget);

    await h.emit(
      tester,
      PhotosUpdated([
        player(id: 'me', name: 'Emma', photoCount: 1),
        player(id: 'p2', name: 'Jake', isHost: true, photoCount: 1),
      ]),
    );

    expect(find.text('Waiting for the host to start'), findsOneWidget);
    expect(find.text('Start game'), findsNothing);
  });

  testWidgets('the leave control is a labelled button, not a bare icon',
      (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    final backButton = find.byTooltip('Leave room');
    expect(backButton, findsOneWidget);
    // A bare GestureDetector around an Icon announces nothing to a screen
    // reader and gives a 24x24 target.
    final semantics = tester.getSemantics(backButton);
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.tooltip, 'Leave room');
    // Material's minimum tap target, supplied by IconButton's padded target.
    expect(semantics.rect.width, greaterThanOrEqualTo(48));
    expect(semantics.rect.height, greaterThanOrEqualTo(48));
  });

  testWidgets('a dropped connection is surfaced with a retry', (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));
    expect(find.text('Connection lost'), findsNothing);

    h.socket.dropConnection();
    await tester.pump();
    await tester.pump();

    expect(find.text('Connection lost'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('leaving asks first, then posts to the server and pops the lobby',
      (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    await tester.tap(find.byTooltip('Leave room'));
    await tester.pumpAndSettle();
    expect(find.text('Leave this game?'), findsOneWidget);
    expect(h.http.countEndingWith('/leave'), 0);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.byType(LobbyScreen), findsOneWidget);
    expect(h.http.countEndingWith('/leave'), 0);

    await tester.tap(find.byTooltip('Leave room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();

    expect(h.http.countEndingWith('/leave'), 1);
    expect(find.byType(LobbyScreen), findsNothing);
  });

  testWidgets('a swipe back asks too', (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Leave this game?'), findsOneWidget);
    expect(find.byType(LobbyScreen), findsOneWidget);
  });

  testWidgets('the host can remove another player, but not themselves',
      (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    expect(find.byTooltip('Remove Jake'), findsOneWidget);
    expect(find.byTooltip('Remove Emma'), findsNothing);
  });

  testWidgets('a non-host is offered no remove buttons at all', (tester) async {
    final h = await harness(isHost: false);
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    expect(find.byTooltip('Remove Jake'), findsNothing);
    expect(find.byTooltip('Remove Emma'), findsNothing);
  });

  testWidgets('removing a player asks first and then posts', (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    await tester.tap(find.byTooltip('Remove Jake'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Jake?'), findsOneWidget);

    // Backing out must not remove anyone.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.http.countEndingWith('/kick'), 0);

    await tester.tap(find.byTooltip('Remove Jake'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(h.http.countEndingWith('/kick'), 1);
  });

  testWidgets('being kicked pops the lobby and says why', (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    await h.emit(
      tester,
      PlayerLeft(
        playerId: 'me',
        kicked: true,
        players: [player(id: 'p2', name: 'Jake', isHost: true)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LobbyScreen), findsNothing);
    // The reason travels on the controller; the lobby hands it to the
    // messenger of the route underneath as it pops. Asserting the snackbar
    // itself needs a route to pop back to, which `pumpScreen` has no room for.
    expect(h.controller.removedFromRoom, 'The host removed you from the room');
  });

  testWidgets('another player leaving just updates the roster', (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));
    expect(find.text('Jake'), findsOneWidget);

    await h.emit(
      tester,
      PlayerLeft(
        playerId: 'p2',
        kicked: false,
        players: [player(id: 'me', name: 'Emma', isHost: true)],
      ),
    );

    expect(find.text('Emma (you)'), findsOneWidget);
    expect(find.text('Jake'), findsNothing);
    expect(find.byType(LobbyScreen), findsOneWidget);
  });

  testWidgets('the host sets rounds and round length from the lobby',
      (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    expect(find.text('5 rounds, 10 seconds each'), findsOneWidget);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('Rounds'), findsOneWidget);
    expect(find.text('Seconds per round'), findsOneWidget);

    await tester.tap(find.byTooltip('More Rounds'));
    await tester.pump();

    final posted = h.http.requests.where((r) => r.url.path.endsWith('/settings'));
    expect(posted, isNotEmpty);
    expect((posted.last as dynamic).body, contains('total_rounds'));
  });

  testWidgets('a broadcast settings change reaches every client',
      (tester) async {
    final h = await harness(isHost: false);
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    await h.emit(
      tester,
      const SettingsUpdated(totalRounds: 9, roundSeconds: 25, hardcore: true),
    );

    // Read-only for a non-host: values shown, no steppers or switch.
    expect(
      find.text('9 rounds, 25 seconds each'),
      findsOneWidget,
    );
    expect(find.textContaining('Hardcore mode:'), findsOneWidget);
    expect(find.text('Change'), findsNothing);
  });

  testWidgets('hardcore is editable until the first photo lands, then locks',
      (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    final switchFinder = find.byType(Switch);
    expect(tester.widget<Switch>(switchFinder).onChanged, isNotNull);

    await h.emit(
      tester,
      PhotosUpdated([
        player(id: 'me', name: 'Emma', isHost: true, photoCount: 1),
        player(id: 'p2', name: 'Jake'),
      ]),
    );

    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(
      find.text('Locked: photos have been added'),
      findsOneWidget,
    );
  });
}
