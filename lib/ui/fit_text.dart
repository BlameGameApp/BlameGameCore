import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Poster type: one line of black caps that fills the box it is given, edge to
/// edge and top to bottom.
///
/// This is how wood-type posters were set. Every line ran to the full measure,
/// so a compositor reached for a wider or narrower face per line rather than a
/// smaller one. Anybody's `wdth` axis does that continuously, so the height of
/// the band sets the size and the axis takes up the difference. Names are 1 to
/// 24 characters: a plain [FittedBox] would leave "Al" and "Maximilian" at
/// wildly different sizes, and here they are the same block of colour.
///
/// Past either end of the axis the line is stretched to fit. That is a choice,
/// not a fallback: a tall band gets tall letters instead of a small word
/// floating in a field of colour.
class FitText extends StatelessWidget {
  final String text;
  final Color color;

  /// What a screen reader says, when [text] was upcased for display.
  final String? semanticsLabel;

  const FitText(
    this.text, {
    super.key,
    required this.color,
    this.semanticsLabel,
  });

  /// `sCapHeight / unitsPerEm`. The band is filled by the caps, not by the line
  /// box, which is why this is measured rather than left to [Text].
  static const double _capHeight = 0.675;

  /// Where the caps sit in a line box [_capHeight] tall: an even-leading line
  /// puts the baseline this far above the bottom edge, so it is pushed back
  /// down. From hhea ascent 0.795 and descent 0.24.
  static const double _baselineShift = 0.06;

  static const double _narrowest = 50;
  static const double _widest = 150;

  static TextStyle _style(double size, double width, Color? color) {
    return TextStyle(
      fontFamily: appFontFamily,
      fontSize: size,
      // Spelled out so it can't inherit Material's body tracking: 0.25 per
      // glyph doesn't sound like much until a 24-letter name overruns the band.
      letterSpacing: 0,
      height: _capHeight,
      leadingDistribution: TextLeadingDistribution.even,
      color: color,
      fontVariations: [
        FontVariation.weight(900),
        FontVariation.width(width),
      ],
    );
  }

  static double _measure(String text, double size, double width) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _style(size, width, null)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final measured = painter.width;
    painter.dispose();
    return measured;
  }

  /// The size and `wdth` for [text] in a box this big, and what is left over
  /// for [Transform] to stretch once the axis can't go any further.
  static ({double size, double width, double scaleX, double scaleY}) fit(
    String text,
    double maxWidth,
    double maxHeight,
  ) {
    var size = maxHeight / _capHeight;
    var width = _narrowest;
    final atNarrowest = _measure(text, size, _narrowest);
    if (atNarrowest >= maxWidth) {
      size *= maxWidth / atNarrowest;
    } else if (_measure(text, size, _widest) <= maxWidth) {
      width = _widest;
    } else {
      var high = _widest;
      for (var i = 0; i < 7; i++) {
        final middle = (width + high) / 2;
        if (_measure(text, size, middle) <= maxWidth) {
          width = middle;
        } else {
          high = middle;
        }
      }
    }
    final measured = _measure(text, size, width);
    return (
      size: size,
      width: width,
      scaleX: measured == 0 ? 1 : maxWidth / measured,
      scaleY: maxHeight / (size * _capHeight),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final (:size, :width, :scaleX, :scaleY) = fit(
          text,
          box.maxWidth,
          box.maxHeight,
        );
        return Align(
          alignment: Alignment.bottomLeft,
          child: Transform(
            alignment: Alignment.bottomLeft,
            transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
            child: Transform.translate(
              offset: Offset(0, size * _baselineShift),
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                // The size already comes from the band, so a system text scale
                // would only push the line back out of it.
                textScaler: TextScaler.noScaling,
                semanticsLabel: semanticsLabel,
                style: _style(size, width, color),
              ),
            ),
          ),
        );
      },
    );
  }
}
