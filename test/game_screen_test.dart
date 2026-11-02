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
    // Jake owns the photo, so the band must say so — this is the payoff of the
    // whole round and used to render for zero frames.
    expect(find.text("It was Jake's photo"), findsOneWidget);

    await unmount(tester);
    h.controller.dispose();
  });

  testWidgets('the guesses stay put from the first second to the reveal',
      (tester) async {
    final h = await inRound(tester, guess: const {'points': 0, 'correct': false});
    final before = tester.getTopLeft(find.text('Jake'));

    await tester.tap(find.text('Jake'));
    await tester.pump();
    await tester.pump();
    expect(tester.getTopLeft(find.text('Jake')), before);

    await h.emit(tester, const RoundRevealed(roundIndex: 0, ownerId: 'me'));
    expect(tester.getTopLeft(find.text('Jake')), before);
    // Both answers are marked with more than a colour.
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNWidgets(2)); // Jake, and Leave.
    expect(find.text('You guessed Jake'), findsOneWidget);

    await unmount(tester);
    h.controller.dispose();
  });

  testWidgets('a swipe back asks first: there is no way back into a game',
      (tester) async {
    final h = await inRound(tester);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Leave this game?'), findsOneWidget);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(h.http.countEndingWith('/leave'), 0);

    await tester.tap(find.text('Stay'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Leave this game?'), findsNothing);
    expect(h.http.countEndingWith('/leave'), 0);

    await unmount(tester);
    h.controller.dispose();
  });

  testWidgets('the leave button asks, then really leaves', (tester) async {
    final h = await inRound(tester);

    await tester.tap(find.byTooltip('Leave game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Leave'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.http.countEndingWith('/leave'), 1);

    await unmount(tester);
    h.controller.dispose();
  });

  testWidgets('the live score badge reflects points as they are won',
      (tester) async {
    final h = await inRound(tester);
    expect(find.text('0 points'), findsOneWidget);

    await h.emit(
      tester,
      const GuessResult(guesserId: 'me', points: 700, correct: true),
    );

    expect(find.text('700 points'), findsOneWidget);

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

  testWidgets('guesses are buttons to a screen reader, not plain text',
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
