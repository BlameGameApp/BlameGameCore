import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_blame/models/game_models.dart';
import 'package:photo_blame/screens/game_screen.dart';
import 'package:photo_blame/screens/home_screen.dart';
import 'package:photo_blame/screens/lobby_screen.dart';
import 'package:photo_blame/screens/results_screen.dart';
import 'package:photo_blame/theme/app_theme.dart';

import 'support/fakes.dart';
import 'support/pump.dart';

/// A full room with every name at the 24-character limit, in the two tightest
/// spots the app has to cope with: the narrowest iPhone, and a small iPhone with
/// the text size turned up. flutter_test's font is far wider than the real one,
/// so these are stricter than any device.
const _cases = <(String, Size, double)>[
  ('the narrowest iPhone', Size(320, 568), 1),
  ('large text', Size(375, 667), 1.5),
];

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

Future<void> _pumpAt(
  WidgetTester tester,
  Widget screen,
  Size size,
  double textScale,
) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await pumpScreen(tester, screen);
  tester.view.physicalSize = size;
  await tester.pump();
}

void main() {
  for (final (name, size, textScale) in _cases) {
    group(name, () {
      testWidgets('the home form fits, keyboard or not', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
        );
        expect(tester.takeException(), isNull);

        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('a full lobby fits', (tester) async {
        final h = await harness(snapshot: _fullRoom);
        await _pumpAt(
          tester,
          LobbyScreen(controller: h.controller),
          size,
          textScale,
        );

        expect(tester.takeException(), isNull);
      });

      testWidgets('a full guess grid fits, with every name on screen', (
        tester,
      ) async {
        final h = await harness(snapshot: _fullRoom);
        h.socket.emit(
          RoundStarted(
            roundIndex: 0,
            photo: const PhotoInfo(id: 'ph', ownerId: 'p1', url: '/p.jpg'),
            roundEndsAt: DateTime.now().millisecondsSinceEpoch + 30000,
          ),
        );
        await tester.pump();
        await _pumpAt(
          tester,
          GameScreen(controller: h.controller),
          size,
          textScale,
        );

        expect(tester.takeException(), isNull);
        // Names scrolled out of reach under a countdown would be no use.
        final names = find.textContaining('Maximilian');
        expect(names, findsNWidgets(12));
        final bottom = tester.getSize(find.byType(GameScreen)).height;
        for (var i = 0; i < 12; i++) {
          expect(tester.getBottomLeft(names.at(i)).dy, lessThan(bottom));
        }

        await tester.pumpWidget(const SizedBox.shrink());
        h.controller.dispose();
      });

      testWidgets('a full leaderboard fits', (tester) async {
        final h = await harness(snapshot: _fullRoom);
        h.socket.emit(
          GameFinished([
            for (final p in h.controller.players)
              player(id: p.id, name: p.name, score: p.score),
          ]),
        );
        await tester.pump();
        await _pumpAt(
          tester,
          ResultsScreen(controller: h.controller),
          size,
          textScale,
        );

        expect(tester.takeException(), isNull);
      });
    });
  }
}
