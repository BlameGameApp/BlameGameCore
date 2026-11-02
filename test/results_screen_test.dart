import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_blame/models/game_models.dart';
import 'package:photo_blame/screens/results_screen.dart';
import 'package:photo_blame/ui/confetti.dart';

import 'support/fakes.dart';
import 'support/pump.dart';

/// Drives the controller to a finished game with the given rankings.
Future<TestHarness> finishedGame(
  WidgetTester tester, {
  bool isHost = true,
  List<GamePlayer>? rankings,
}) async {
  final h = await harness(isHost: isHost);
  h.socket.emit(GameFinished(rankings ??
      [
        player(id: 'p2', name: 'Jake', score: 2400),
        player(id: 'me', name: 'Emma', score: 1500, isHost: true),
      ]));
  await tester.pump();
  return h;
}

void main() {
  testWidgets('leaving tells the server, so nobody waits on a ghost',
      (tester) async {
    final h = await finishedGame(tester);
    await pumpScreen(tester, ResultsScreen(controller: h.controller));

    await tester.tap(find.text('Leave game'));
    await tester.pumpAndSettle();

    expect(h.http.countEndingWith('/leave'), 1);
  });

  testWidgets('the winner is named and celebrated, the last place is teased',
      (tester) async {
    final h = await finishedGame(tester);
    await pumpScreen(tester, ResultsScreen(controller: h.controller));

    expect(find.text('Jake wins!'), findsOneWidget);
    expect(find.text('Top detective'), findsOneWidget);
    expect(find.text('You, prime suspect'), findsOneWidget);
    expect(find.byType(Confetti), findsOneWidget);
  });

  testWidgets('winning on your own phone says so', (tester) async {
    final h = await finishedGame(
      tester,
      rankings: [
        player(id: 'me', name: 'Emma', score: 2400, isHost: true),
        player(id: 'p2', name: 'Jake', score: 1500),
      ],
    );
    await pumpScreen(tester, ResultsScreen(controller: h.controller));

    expect(find.text('You win!'), findsOneWidget);
    expect(find.text('You, top detective'), findsOneWidget);
  });

  testWidgets('a tie has no winner to celebrate', (tester) async {
    final h = await finishedGame(
      tester,
      rankings: [
        player(id: 'p2', name: 'Jake', score: 900),
        player(id: 'me', name: 'Emma', score: 900, isHost: true),
      ],
    );
    await pumpScreen(tester, ResultsScreen(controller: h.controller));

    expect(find.text("It's a tie!"), findsOneWidget);
    expect(find.textContaining('etective'), findsNothing);
    expect(find.textContaining('uspect'), findsNothing);
    expect(find.byType(Confetti), findsNothing);
  });

  testWidgets('a scoreless game is called what it is', (tester) async {
    final h = await finishedGame(
      tester,
      rankings: [
        player(id: 'p2', name: 'Jake'),
        player(id: 'me', name: 'Emma', isHost: true),
      ],
    );
    await pumpScreen(tester, ResultsScreen(controller: h.controller));

    expect(find.text('Nobody scored!'), findsOneWidget);
    expect(find.textContaining('uspect'), findsNothing);
    expect(find.byType(Confetti), findsNothing);
  });

  testWidgets('no confetti for anyone who asked for reduced motion',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final h = await finishedGame(tester);
    await pumpScreen(tester, ResultsScreen(controller: h.controller));

    expect(
      find.descendant(
        of: find.byType(Confetti),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('ranks players by score with the winner on top', (tester) async {
    final h = await finishedGame(tester);
    await pumpScreen(tester, ResultsScreen(controller: h.controller));

    expect(find.text('Jake'), findsWidgets);
    expect(find.text('Emma'), findsWidgets);
    expect(find.text('2400 points'), findsOneWidget);
    expect(find.text('1500 points'), findsOneWidget);
  });

  testWidgets('the host can start a new round', (tester) async {
    final h = await finishedGame(tester, isHost: true);
    await pumpScreen(tester, ResultsScreen(controller: h.controller));

    expect(find.text('Play again'), findsOneWidget);
  });

  testWidgets('a non-host cannot start a new round', (tester) async {
    final h = await finishedGame(tester, isHost: false);
    await pumpScreen(tester, ResultsScreen(controller: h.controller));

    expect(find.text('Play again'), findsNothing);
  });

  testWidgets('the leaderboard is live, not a frozen snapshot', (tester) async {
    // _onChange used to handle only navigation and never rebuild, so a late
    // event left the screen showing stale results.
    final h = await finishedGame(tester);
    await pumpScreen(tester, ResultsScreen(controller: h.controller));
    expect(find.text('2400 points'), findsOneWidget);

    await h.emit(
      tester,
      GameFinished([
        player(id: 'p2', name: 'Jake', score: 9100),
        player(id: 'me', name: 'Emma', score: 1500, isHost: true),
      ]),
    );

    expect(find.text('9100 points'), findsOneWidget);
    expect(find.text('2400 points'), findsNothing);
  });

  testWidgets('an empty leaderboard does not crash', (tester) async {
    final h = await finishedGame(tester, rankings: []);
    await pumpScreen(tester, ResultsScreen(controller: h.controller));

    expect(tester.takeException(), isNull);
  });
}
