import 'package:flutter/material.dart';

import 'player_cosmetics.dart';
import 'player_token.dart';

/// "PHOTO BLAME" spelled out in board-game pieces that drop onto the table.
///
/// Seats are picked by hand: marigold, lime and tangerine would disappear into
/// the marigold header this sits on.
const List<(String, int)> _photo = [
  ('P', 1),
  ('H', 2),
  ('O', 4),
  ('T', 6),
  ('O', 9),
];
const List<(String, int)> _blame = [
  ('B', 3),
  ('L', 7),
  ('A', 10),
  ('M', 11),
  ('E', 1),
];

class TitleTokens extends StatelessWidget {
  final double radius;

  const TitleTokens({super.key, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'Photo Blame',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_row(context, _photo, 0), _row(context, _blame, 5)],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, List<(String, int)> letters, int offset) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, (letter, seat)) in letters.indexed)
          _Dropping(
            order: offset + i,
            child: PlayerToken(
              name: letter,
              piece: playerPieces[seat],
              radius: radius,
            ),
          ),
      ],
    );
  }
}

/// Falls into place on first build, one piece after another. Over in under a
/// second and never in the way, since the form below is usable throughout.
class _Dropping extends StatelessWidget {
  final int order;
  final Widget child;

  const _Dropping({required this.order, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final start = order * 0.05;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 850),
      curve: Interval(start, start + 0.5, curve: Curves.easeOutBack),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, -56 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
