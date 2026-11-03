import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_blame/models/game_models.dart';
import 'package:photo_blame/screens/game_screen.dart';
import 'package:photo_blame/state/game_controller.dart';

import 'support/pump.dart';

/// A round that ends well in the future, so the countdown stays positive.
RoundStarted _round({int index = 0, String owner = 'p2'}) => RoundStarted(
      roundIndex: index,
      photo: PhotoInfo(id: 'ph$index', ownerId: owner, url: '/p.jpg'),
      roundEndsAt: DateTime.now().millisecondsSinceEpoch + 30000,
    );

/// GameScreen runs a periodic countdown; unmount it so the timer is cancelled
/// and the test doesn't fail with a pending timer.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

Future<TestHarness> inRound(WidgetTester tester, {Object? guess}) async {
  final h = await harness(guess: guess ?? const {'points': 800, 'correct': true});
  h.socket.emit(_round());
  await tester.pump();
  await pumpScreen(tester, GameScreen(controller: h.controller));
  return h;
}

void main() {
  testWidgets('offers every player as a guess, including yourself',
      (tester) async {
    final h = await inRound(tester);

    expect(find.text('Emma'), findsOneWidget);
    expect(find.text('Jake'), findsOneWidget);

    await unmount(tester);
    h.controller.dispose();
  });

  testWidgets('guessing locks the round and shows the points earned',
      (tester) async {
    final h = await inRound(tester);

    await tester.tap(find.text('Jake'));
    await tester.pump();
    await tester.pump();

    expect(h.controller.hasGuessedThisRound, isTrue);
    // The instant feedback banner reports the player's own result before the
    // round reveals the owner to everyone.
    h.socket.emit(const GuessResult(guesserId: 'me', points: 800, correct: true));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('800'), findsWidgets);

    await unmount(tester);
    h.controller.dispose();
  });

  testWidgets('a failed guess is reported and the round unlocks',
      (tester) async {
    final h = await inRound(tester, guess: 500);

    await tester.tap(find.text('Jake'));
    await tester.pump();
    await tester.pump();

    expect(
      h.controller.hasGuessedThisRound,
      isFalse,
      reason: 'a transient failure must not lock the player out',
    );
    expect(find.textContaining('Guess failed'), findsOneWidget);

    await unmount(tester);
    h.controller.dispose();
  });

  testWidgets('the reveal names whose photo it was', (tester) async {
    final h = await inRound(tester);

    await h.emit(tester, const RoundRevealed(roundIndex: 0, ownerId: 'p2'));

    expect(h.controller.phase, GamePhase.revealed);
    // Jake owns the photo, so the banner must say so — this is the payoff of
    // the whole round and used to render for zero frames.
    expect(find.textContaining('Jake'), findsWidgets);

    await unmount(tester);
    h.controller.dispose();
  });

  testWidgets('the reveal shows a scoreboard in the server\'s order',
      (tester) async {
    final h = await inRound(tester);

    // Jake leads. The server ranks; the client must render that order as-is.
    await h.emit(
      tester,
      const RoundRevealed(roundIndex: 0, ownerId: 'p2', standings: [
        GamePlayer(id: 'p2', name: 'Jake', score: 800),
        GamePlayer(id: 'me', name: 'Emma', score: 300),
      ]),
    );

    expect(find.text('800'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
    final jake = tester.getTopLeft(find.text('800')).dy;
    final emma = tester.getTopLeft(find.text('300')).dy;
    expect(jake, lessThan(emma), reason: 'leader is rendered first');

    await unmount(tester);
    h.controller.dispose();
  });

  testWidgets('the live score badge reflects points as they are won',
      (tester) async {
    final h = await inRound(tester);
    expect(find.text('0'), findsWidgets);

    await h.emit(
      tester,
      const GuessResult(guesserId: 'me', points: 700, correct: true),
    );

    expect(find.text('700'), findsOneWidget);

    await unmount(tester);
    h.controller.dispose();
  });

  testWidgets('a dropped connection is surfaced mid-game', (tester) async {
    final h = await inRound(tester);

    h.socket.dropConnection();
    await tester.pump();
    await tester.pump();

    expect(find.text('Connection lost'), findsOneWidget);

    await unmount(tester);
    h.controller.dispose();
  });

  testWidgets('the round photo is decoded at display size, not source size',
      (tester) async {
    final h = await inRound(tester);

    final image = tester.widget<Image>(find.byType(Image));
    // Without cacheWidth a 4032px camera original decodes to ~48MB for a
    // ~350px box and thrashes the image cache within a few rounds.
    expect(image.width, isNotNull);
    final provider = image.image;
    expect(
      provider.runtimeType.toString(),
      contains('ResizeImage'),
      reason: 'cacheWidth should wrap the provider in a ResizeImage',
    );

    await unmount(tester);
    h.controller.dispose();
  });

  testWidgets('guess chips are buttons to a screen reader, not plain text',
      (tester) async {
    final handle = tester.ensureSemantics();
    final h = await inRound(tester);

    // They were bare GestureDetectors, which VoiceOver reads out as static
    // text with no hint that it can be tapped.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Guess Jake')),
      matchesSemantics(
        label: 'Guess Jake',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasSelectedState: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );

    handle.dispose();
    await unmount(tester);
    h.controller.dispose();
  });
}
