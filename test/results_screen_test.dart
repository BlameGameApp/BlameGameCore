import 'package:flutter_test/flutter_test.dart';
import 'package:photo_blame/models/game_models.dart';
import 'package:photo_blame/screens/results_screen.dart';

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
