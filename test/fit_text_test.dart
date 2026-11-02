import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_blame/theme/app_theme.dart';
import 'package:photo_blame/ui/fit_text.dart';

void main() {
  // The real font, not flutter_test's placeholder: FitText is entirely about
  // what the wdth axis does, and the placeholder doesn't have one.
  setUpAll(() async {
    final bytes = File('assets/fonts/Anybody-Variable.ttf').readAsBytesSync();
    final loader = FontLoader(appFontFamily)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  const width = 370.0;
  const height = 64.0;

  group('FitText.fit', () {
    test('a mid-length name is set by the axis alone, undistorted', () {
      final fit = FitText.fit('TESTER', width, height);
      expect(fit.width, inExclusiveRange(50, 150));
      expect(fit.scaleX, closeTo(1, 0.02));
      expect(fit.scaleY, closeTo(1, 0.001));
    });

    test('a short name goes to the widest cut before stretching', () {
      final fit = FitText.fit('AL', width, height);
      expect(fit.width, 150);
      expect(fit.scaleX, greaterThan(1));
    });

    test('a long name goes to the narrowest cut, then shrinks to fit', () {
      final fit = FitText.fit('MAXIMILIAN VON HOHENZOLL', width, height);
      expect(fit.width, 50);
      expect(fit.scaleX, closeTo(1, 0.001));
      // Smaller type, stretched back up so every band's name is equally tall.
      expect(fit.scaleY, greaterThan(1));
    });

    test('a tall band gets tall letters', () {
      final fit = FitText.fit('TESTER', width, 340);
      expect(fit.width, 50);
      expect(fit.scaleY, greaterThan(1));
    });

    test('every length from 1 to 24 characters fills the box', () {
      for (var length = 1; length <= 24; length++) {
        final name = 'M' * length;
        final fit = FitText.fit(name, width, height);
        final painter = TextPainter(
          text: TextSpan(
            text: name,
            style: TextStyle(
              fontFamily: appFontFamily,
              fontSize: fit.size,
              letterSpacing: 0,
              fontVariations: [
                FontVariation.weight(900),
                FontVariation.width(fit.width),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(
          painter.width * fit.scaleX,
          closeTo(width, 0.5),
          reason: '$length characters',
        );
        painter.dispose();
      }
    });
  });

  testWidgets('tracking inherited from the theme cannot widen the line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: DefaultTextStyle(
            style: TextStyle(letterSpacing: 5),
            child: SizedBox(
              width: width,
              height: height,
              child: FitText('MAXIMILIAN VON HOHENZOLL', color: Colors.black),
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style!.letterSpacing, 0);
  });
}
