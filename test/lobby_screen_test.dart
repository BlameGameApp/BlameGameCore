import 'package:flutter/material.dart';
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
    expect(find.text('EMMA'), findsOneWidget);
    expect(find.text('You, hosting'), findsOneWidget);
    expect(find.text('JAKE'), findsOneWidget);
  });

  testWidgets('start is blocked until two people have added photos',
      (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    // Two players, but nobody has uploaded.
    expect(find.text('Need photos from 2+ players'), findsOneWidget);
    expect(find.text('Start game'), findsNothing);

    await h.emit(
      tester,
      PhotosUpdated([
        player(id: 'me', name: 'Emma', isHost: true, photoCount: 3),
        player(id: 'p2', name: 'Jake', photoCount: 1),
      ]),
    );

    expect(find.text('Start game'), findsOneWidget);
  });

  testWidgets('one uploader is not enough', (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    await h.emit(
      tester,
      PhotosUpdated([
        player(id: 'me', name: 'Emma', isHost: true, photoCount: 5),
        player(id: 'p2', name: 'Jake'),
      ]),
    );

    expect(find.text('Need photos from 2+ players'), findsOneWidget);
  });

  testWidgets('players show real readiness, not a decorative tick',
      (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    // Nobody has uploaded, and every band says so.
    expect(find.text('No photos yet'), findsNWidgets(2));

    await h.emit(
      tester,
      PhotosUpdated([
        player(id: 'me', name: 'Emma', isHost: true, photoCount: 1),
        player(id: 'p2', name: 'Jake', photoCount: 3),
      ]),
    );

    expect(find.text('No photos yet'), findsNothing);
    expect(find.text('1 photo'), findsOneWidget);
    expect(find.text('3 photos'), findsOneWidget);
  });

  testWidgets('a non-host sees no start button', (tester) async {
    final h = await harness(isHost: false);
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    expect(find.text('Start game'), findsNothing);
    expect(find.text('Need photos from 2+ players'), findsNothing);
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

  testWidgets('leaving posts to the server and pops the lobby', (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    await tester.tap(find.byTooltip('Leave room'));
    await tester.pumpAndSettle();

    expect(h.http.countEndingWith('/leave'), 1);
    expect(find.byType(LobbyScreen), findsNothing);
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
    expect(find.text('JAKE'), findsOneWidget);

    await h.emit(
      tester,
      PlayerLeft(
        playerId: 'p2',
        kicked: false,
        players: [player(id: 'me', name: 'Emma', isHost: true)],
      ),
    );

    expect(find.text('EMMA'), findsOneWidget);
    expect(find.text('JAKE'), findsNothing);
    expect(find.byType(LobbyScreen), findsOneWidget);
  });

  testWidgets('the host sets rounds and round length from the lobby',
      (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

    expect(find.text('Rounds'), findsOneWidget);
    expect(find.text('Seconds'), findsOneWidget);

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
    expect(find.textContaining('Hardcore:'), findsOneWidget);
    expect(find.byTooltip('More Rounds'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('hardcore is editable until the first photo lands, then locks',
      (tester) async {
    final h = await harness();
    await pumpScreen(tester, LobbyScreen(controller: h.controller));

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
