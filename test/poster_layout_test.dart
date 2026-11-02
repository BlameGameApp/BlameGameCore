import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_blame/models/game_models.dart';
import 'package:photo_blame/screens/game_screen.dart';
import 'package:photo_blame/screens/lobby_screen.dart';
import 'package:photo_blame/screens/results_screen.dart';
import 'package:photo_blame/ui/band.dart';

import 'support/fakes.dart';
import 'support/pump.dart';

/// The worst room on the smallest phone the app supports: an iPhone SE, full,
/// with every name at the 24-character limit. A stack of bands has nowhere to
/// put an overflow, so these fail on any flex that doesn't fit.
const _smallPhone = Size(375, 667);

final _fullRoom = <String, Object?>{
  'state': 'lobby',
  'round_seconds': 10,
  'players': [
    for (var i = 0; i < 12; i++)
      {
        'id': i == 0 ? 'me' : 'p$i',
        'name': 'Maximilian von Hohenz$i'.padRight(24, 'x').substring(0, 24),
        'is_host': i == 0,
        'score': (12 - i) * 100,
      },
  ],
};

Future<void> _pumpSmall(WidgetTester tester, Widget screen) async {
  await pumpScreen(tester, screen);
  tester.view.physicalSize = _smallPhone;
  await tester.pump();
}

void main() {
  testWidgets('a full lobby fits a small phone', (tester) async {
    final h = await harness(snapshot: _fullRoom);
    await _pumpSmall(tester, LobbyScreen(controller: h.controller));

    expect(tester.takeException(), isNull);
  });

  testWidgets('a full lobby fits at the largest text size it allows', (
    tester,
  ) async {
    final h = await harness(snapshot: _fullRoom);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpSmall(tester, LobbyScreen(controller: h.controller));

    expect(tester.takeException(), isNull);
  });

  testWidgets('a lobby survives the keyboard from the previous route', (
    tester,
  ) async {
    final h = await harness();
    await _pumpSmall(tester, LobbyScreen(controller: h.controller));

    // The keyboard is still on its way out when the lobby arrives.
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a full guess grid fits a small phone', (tester) async {
    final h = await harness(snapshot: _fullRoom);
    h.socket.emit(
      RoundStarted(
        roundIndex: 0,
        photo: const PhotoInfo(id: 'ph', ownerId: 'p1', url: '/p.jpg'),
        roundEndsAt: DateTime.now().millisecondsSinceEpoch + 30000,
      ),
    );
    await tester.pump();
    await _pumpSmall(tester, GameScreen(controller: h.controller));

    expect(find.byType(PlayerBand), findsNWidgets(12));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    h.controller.dispose();
  });

  testWidgets('a full leaderboard fits a small phone', (tester) async {
    final h = await harness(snapshot: _fullRoom);
    h.socket.emit(
      GameFinished([
        for (final p in h.controller.players)
          player(id: p.id, name: p.name, score: p.score),
      ]),
    );
    await tester.pump();
    await _pumpSmall(tester, ResultsScreen(controller: h.controller));

    expect(tester.takeException(), isNull);
  });

  testWidgets('the winner gets the most room when scores differ', (
    tester,
  ) async {
    final h = await harness();
    h.socket.emit(
      GameFinished([
        player(id: 'p2', name: 'Jake', score: 2400),
        player(id: 'me', name: 'Emma', score: 300),
      ]),
    );
    await tester.pump();
    await pumpScreen(tester, ResultsScreen(controller: h.controller));

    Size band(String name) => tester.getSize(
      find.ancestor(of: find.text(name), matching: find.byType(PlayerBand)),
    );
    expect(band('JAKE').height, greaterThan(band('EMMA').height));
  });
}
