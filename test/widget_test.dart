// Widget test for the home screen. Runs headless with `flutter test` — no
// emulator. It pumps the app and checks the home UI renders, without touching
// the network (we never tap Create/Join here).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photo_blame/main.dart';

void main() {
  testWidgets('Home screen renders title and actions', (tester) async {
    await tester.pumpWidget(const PhotoBlameApp());

    expect(find.text('Guess whose photo it is'), findsOneWidget);
    expect(find.text('Join game'), findsOneWidget);
    expect(find.text('Start a new game'), findsOneWidget);

    // Name and game-code fields are present.
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('the title reads as one name to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const PhotoBlameApp());

    expect(find.bySemanticsLabel('Photo Blame'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('a name is required, instead of becoming a silent "Player"',
      (tester) async {
    await tester.pumpWidget(const PhotoBlameApp());

    await tester.tap(find.text('Start a new game'));
    await tester.pump();

    expect(find.text('Enter your name'), findsOneWidget);
  });

  testWidgets('joining needs a whole game code', (tester) async {
    await tester.pumpWidget(const PhotoBlameApp());

    await tester.enterText(find.byType(TextField).first, 'Emma');
    await tester.enterText(find.byType(TextField).last, 'abc');
    await tester.tap(find.text('Join game'));
    await tester.pump();

    expect(find.text('Enter the 5-character code'), findsOneWidget);
    // Typed in lower case, shown as the code it will be matched against.
    expect(find.text('ABC'), findsOneWidget);
  });
}
